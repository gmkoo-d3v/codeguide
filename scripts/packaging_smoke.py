#!/usr/bin/env python3
"""Read-only packaging smoke tool: classify every path under the skill root.

Forces every entry in the skill tree to be explicitly one of three things:

  - SHIP: would end up in a distributed package.
  - DEV-ARTIFACT: never ships, but is an expected/normal part of a working
    tree (VCS metadata, tool caches, scratch space).
  - UNKNOWN: matches neither list. Exits 1 by default (--no-exit-code to
    report only) so an unclassified stray fails a gate loudly instead of
    silently riding along into (or out of) a package.

Classification, first match wins, in this order (see classify()'s docstring
for the full rationale, including a deliberate deviation from the plan
prose's bullet order):

  1. DEV-ARTIFACT "anywhere" rules: a path segment of ``__pycache__``, a
     ``.pyc`` file, a ``.gitignore`` file, or a ``.DS_Store`` file, at any
     depth.
  2. DEV-ARTIFACT root-rooted directories: ``.git/**``, ``.serena/**``,
     ``.pytest_cache/**``, ``.gemini/**``, ``tmp/**``.
  3. SHIP: the exact top-level files ``SKILL.md``, ``README.md``,
     ``README.en.md``, ``requirements-dev.txt``, and the root-rooted directories
     ``agents/**``, ``case-studies/**``, ``config/**``, ``references/**``,
     ``scripts/**``, ``tests/**``. (``case-studies/`` holds the reports the
     shipped README links to, so a packaged README never carries dangling
     links.)
  4. Everything else: UNKNOWN.

Symlinks: classified at their OWN path, exactly like any other entry, and
NEVER followed -- a symlink to a directory is reported once, as itself, and
its target's contents are never visited. This holds even for a dangling
(broken-target) symlink, since classification is pure path-string matching
and never stats or reads through the link. This is deliberate: a symlink
must not be usable to smuggle unclassified content into (or out of) the
manifest via directory traversal, and a dangling symlink must not crash the
scan.

Empty directories are classified too (using the same rules, against the
directory's own path) because a files-only walk would make them invisible --
concretely, the live skill tree has at least one stray empty ``test/``
directory (singular, not the allowlisted ``tests/``) that this tool must
surface as UNKNOWN. A non-empty, non-symlink directory is never classified
or counted itself; only the files (and symlinks, and empty directories)
under it are, so a directory's own entry never double-counts against its
contents.

Paths containing spaces (or any other characters) are handled safely because
this tool never shells out or splits a path as a string -- it walks the
filesystem with os.scandir/pathlib and matches path components by exact
equality, never by naive string prefix/substring or shell-word splitting.

Deterministic and READ-ONLY: no writes, no deletion, no move -- this tool
only ever reads directory entries and reports a classification. Disposition
of anything it reports (delete, reclassify, allowlist) is a separate,
explicit, human-reviewed step.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from collections import Counter
from pathlib import Path

sys.dont_write_bytecode = True  # keep the tool read-only: no .pyc writes into scripts/ on import

# --- classification rules ---------------------------------------------------

SHIP_EXACT_FILES = ("SKILL.md", "README.md", "README.en.md", "requirements-dev.txt")
SHIP_ROOT_DIRS = ("agents", "case-studies", "config", "references", "scripts", "tests")

DEV_ARTIFACT_ROOT_DIRS = (".git", ".serena", ".pytest_cache", ".gemini", "tmp")

# Fixed print order for the text-mode DEV-ARTIFACT summary breakdown: every
# label is always shown, even at 0, so a rule that currently matches nothing
# is exactly as visible as one that matches everything (never silently
# omitted from the report).
DEV_ARTIFACT_LABELS_ORDER = (
    ".git/**",
    ".gitignore",
    ".serena/**",
    ".pytest_cache/**",
    ".gemini/**",
    ".DS_Store",
    "tmp/**",
    "__pycache__/**",
    "*.pyc",
)


def classify(rel_parts: tuple[str, ...]) -> tuple[str, str]:
    """Classify one relative path. Returns (category, rule_label).

    First match wins. DEV-ARTIFACT's "anywhere" basename/segment rules
    (.gitignore, .DS_Store, any __pycache__ path segment, any *.pyc file)
    are checked BEFORE the SHIP root-directory globs on purpose: the live
    skill tree has __pycache__/ and .DS_Store cruft nested INSIDE scripts/,
    tests/, and references/ (all SHIP-allowlisted directories), and the
    plan's DEV-ARTIFACT list gives these rules their recursive "**/" form
    precisely so nested cruft stays excluded no matter where it appears.
    Checking SHIP's broader "scripts/**"-style directory globs first would
    silently reclassify every nested __pycache__/*.pyc and .DS_Store as
    shippable, which defeats the point of having those rules at all. This
    precedence is an implementation judgment call -- the plan prose lists
    the SHIP bullet first in the enumeration -- flagged explicitly for the
    review round rather than guessed silently.

    Root-directory matches (both DEV-ARTIFACT's .git/.serena/etc. and SHIP's
    agents/config/etc.) compare the path's FIRST COMPONENT by exact string
    equality, never by substring/prefix matching on the joined path string.
    That is a deliberate hostile-path defense: a sibling name like
    "scripts2/evil.py" or "tests-legacy/old.py" must fall through to
    UNKNOWN, not slip into the "scripts/**"/"tests/**" bucket because its
    name happens to start with an allowlisted directory name.

    The same root-component check also means an EMPTY allowlisted or
    dev-artifact directory (no files of its own to be classified by) still
    classifies correctly via its own path -- e.g. an empty "agents/" ships,
    an empty ".git/objects/" is still a dev artifact -- exactly the same way
    an empty, unrecognized directory (e.g. the live tree's stray "test/")
    falls through to UNKNOWN.
    """
    basename = rel_parts[-1]

    if basename == ".gitignore":
        return "DEV-ARTIFACT", ".gitignore"
    if basename == ".DS_Store":
        return "DEV-ARTIFACT", ".DS_Store"
    if basename == "__pycache__" or "__pycache__" in rel_parts[:-1]:
        return "DEV-ARTIFACT", "__pycache__/**"
    if basename.endswith(".pyc"):
        return "DEV-ARTIFACT", "*.pyc"

    root = rel_parts[0]
    if root in DEV_ARTIFACT_ROOT_DIRS:
        return "DEV-ARTIFACT", f"{root}/**"

    if len(rel_parts) == 1 and basename in SHIP_EXACT_FILES:
        return "SHIP", basename
    if root in SHIP_ROOT_DIRS:
        return "SHIP", f"{root}/**"

    return "UNKNOWN", ""


# --- walking -----------------------------------------------------------------


def iter_classifiable_paths(skill_root: Path):
    """Yield every path under skill_root that needs its own classification.

    That is: every regular file, every symlink (classified at its own path,
    NEVER followed -- see the module docstring), and every directory that is
    completely empty (zero entries of any kind). A non-empty, non-symlink
    directory is a pure traversal container -- it is never itself yielded,
    only its contents are -- so it is never double-counted against them.

    This is a manual stack-based scan rather than os.walk. os.walk's default
    followlinks=False still silently DROPS symlinked directories: they are
    listed in dirnames (for the caller's information only) but never
    traversed AND never yielded in filenames either, so a caller that only
    classifies filenames would never see them at all. Handling directory
    entries via os.scandir/DirEntry.is_symlink() directly lets a symlinked
    directory be reported (once, as itself) and pruned from descent in the
    same step, closing that gap.
    """
    stack = [skill_root]
    while stack:
        current = stack.pop()
        try:
            entries = sorted(os.scandir(current), key=lambda e: e.name)
        except OSError:
            # Unreadable directory: report the directory itself so it still
            # shows up in the manifest instead of silently vanishing.
            if current != skill_root:
                yield current.relative_to(skill_root)
            continue

        if not entries:
            if current != skill_root:
                yield current.relative_to(skill_root)
            continue

        for entry in entries:
            entry_path = Path(entry.path)
            if entry.is_symlink():
                yield entry_path.relative_to(skill_root)
                continue
            if entry.is_dir():
                stack.append(entry_path)
                continue
            yield entry_path.relative_to(skill_root)


class Result:
    __slots__ = ("ship_count", "ship_paths", "dev_artifact_count", "dev_artifact_by_rule", "unknown")

    def __init__(self) -> None:
        self.ship_count = 0
        self.ship_paths: list[str] = []
        self.dev_artifact_count = 0
        self.dev_artifact_by_rule: Counter[str] = Counter()
        self.unknown: list[str] = []


def scan(skill_root: Path) -> Result:
    result = Result()
    for rel_path in iter_classifiable_paths(skill_root):
        rel_str = rel_path.as_posix()
        category, label = classify(rel_path.parts)
        if category == "SHIP":
            result.ship_count += 1
            result.ship_paths.append(rel_str)
        elif category == "DEV-ARTIFACT":
            result.dev_artifact_count += 1
            result.dev_artifact_by_rule[label] += 1
        else:
            result.unknown.append(rel_str)

    result.ship_paths.sort()
    result.unknown.sort()
    return result


# --- rendering ---------------------------------------------------------------


def render_text(result: Result, skill_root: Path, manifest: bool) -> str:
    lines = [f"# Packaging Smoke Report ({skill_root})", ""]
    lines.append(f"- ship_count: {result.ship_count}")
    lines.append(f"- dev_artifact_count: {result.dev_artifact_count}")
    lines.append(f"- unknown_count: {len(result.unknown)}")
    lines.append("")
    lines.append("## DEV-ARTIFACT summary")
    for label in DEV_ARTIFACT_LABELS_ORDER:
        lines.append(f"  {label}: {result.dev_artifact_by_rule.get(label, 0)}")
    lines.append("")
    lines.append(f"## UNKNOWN ({len(result.unknown)})")
    if result.unknown:
        for path in result.unknown:
            lines.append(f"  {path}")
    else:
        lines.append("  (none)")
    if manifest:
        lines.append("")
        lines.append(f"## SHIP manifest ({result.ship_count})")
        for path in result.ship_paths:
            lines.append(f"  {path}")
    return "\n".join(lines)


def render_json(result: Result, manifest: bool) -> str:
    payload = {
        "schema": "codeguide-packaging-smoke/1",
        "ship_count": result.ship_count,
        "dev_artifact_count": result.dev_artifact_count,
        "unknown": result.unknown,
    }
    if manifest:
        payload["ship_manifest"] = result.ship_paths
    return json.dumps(payload)


def _default_skill_root() -> Path:
    """Return the git repo that contains this script (the skill root).

    Same policy, and same rationale, as validator_rule_coverage.py's
    _default_project_root(): deliberately independent of the docs-oriented
    root resolution used elsewhere in this package (which can hop UP to a
    parent docs-SoR repo when the skill package has no docs/ of its own).
    This tool's root is always "the repo this script lives in."
    """
    script_dir = Path(__file__).resolve().parent
    try:
        result = subprocess.run(
            ["git", "-C", str(script_dir), "rev-parse", "--show-toplevel"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        top = result.stdout.strip()
        if top:
            return Path(top).resolve(strict=False)
    except (FileNotFoundError, subprocess.SubprocessError):
        pass
    return script_dir.parent  # scripts/ -> repo root fallback when git is unavailable


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Read-only packaging smoke tool: classify every path under the skill root as "
        "SHIP, DEV-ARTIFACT, or UNKNOWN."
    )
    parser.add_argument(
        "--skill-root",
        help="Skill root to scan (default: the git repo containing this script).",
    )
    parser.add_argument("--format", choices=["text", "json"], default="text", help="Output format (default: text).")
    parser.add_argument(
        "--manifest",
        action="store_true",
        help="Include the full SHIP path list (ship_manifest in JSON; a SHIP manifest section in text).",
    )
    parser.add_argument(
        "--no-exit-code",
        action="store_true",
        help="Report only; exit 0 even when UNKNOWN paths are found (default: exit 1 on any UNKNOWN).",
    )
    args = parser.parse_args(argv)

    skill_root = (
        Path(args.skill_root).expanduser().resolve(strict=False) if args.skill_root else _default_skill_root()
    )
    if not skill_root.is_dir():
        print(f"error: skill root is not a directory: {skill_root}", file=sys.stderr)
        return 2

    result = scan(skill_root)

    if args.format == "json":
        print(render_json(result, args.manifest))
    else:
        print(render_text(result, skill_root, args.manifest))

    if result.unknown and not args.no_exit_code:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
