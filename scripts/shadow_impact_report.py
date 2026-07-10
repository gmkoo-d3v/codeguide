#!/usr/bin/env python3
"""Read-only shadow impact report.

Given a set of changed source files (a git range, the working tree, or an explicit
list), report which shadow docs declare those files in `source_of_truth_paths` yet
were NOT themselves refreshed in the same change set. This answers the session
question "I changed apps/foo/**, but did I refresh the shadow doc that summarizes it?"

This tool is deterministic and READ-ONLY. It never writes shadow content and never
auto-applies anything (YAGNI: no automatic shadow apply). It only reports impact.

Change-set sources (pick one):
  --range <git-range>       Files changed in a git range, e.g. main...HEAD or HEAD~1..HEAD.
  --changed-file <path>     Explicit changed path (repeatable); project-root relative or absolute.
  (default)                 Working tree: tracked changes vs HEAD plus untracked files.

Exit code is 0 by default (a report). With --exit-code it exits 1 when at least one
impacted shadow doc was not refreshed, for use in a pre-commit hook or CI reminder.

Known limitations (split-root layouts):
- Refresh detection unions the DOCS repo's working-tree/untracked changes only,
  so a post-commit audit (--range over source history after the docs refresh was
  already committed) over-reports NEEDS REFRESH. Fail-noisy by design.
- When the docs root is NOT itself inside a git repository, git-derived change
  sets cannot observe docs-side refreshes at all; impacted docs are then reported
  as `refresh state unknown` (a third status that never fails --exit-code) with a
  stderr warning, instead of a permanently false NEEDS REFRESH. Remediate by
  tracking the docs root in git or passing the change set via --changed-file.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from codeguide_paths import _git_toplevel, source_root_for  # DRY: shared source-repo resolution policy
from shadow_source_digest import read_source_paths  # DRY: same parser as the digest tool


def project_root_from(raw: str) -> Path:
    # Use the CLI project root verbatim (absolute) for locating docs/shadow and for
    # resolving source_of_truth_paths. Do NOT collapse it to the git top-level: a
    # monorepo subproject keeps its own docs/shadow, and this repo's own layout puts
    # docs/ one level ABOVE the git repo. git_root (below) is used only to expand
    # git-diff paths, which git prints relative to the git top-level.
    return Path(raw).resolve(strict=False)


def git_ok(args: list[str], cwd: Path) -> bool:
    try:
        subprocess.run(
            ["git", "-C", str(cwd), *args],
            capture_output=True, text=True, check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return False
    return True


def git_lines(args: list[str], cwd: Path) -> list[str]:
    try:
        out = subprocess.run(
            ["git", "-C", str(cwd), *args],
            capture_output=True, text=True, check=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:  # pragma: no cover - surfaced to caller
        raise RuntimeError(f"git {' '.join(args)} failed: {exc}") from None
    return [line for line in out.stdout.splitlines() if line.strip()]


def changed_abs_paths(args: argparse.Namespace, project_root: Path, git_root: Path | None) -> set[Path]:
    paths: set[Path] = set()
    if args.changed_file:
        for raw in args.changed_file:
            candidate = Path(raw)
            target = candidate if candidate.is_absolute() else (project_root / candidate)
            paths.add(target.resolve(strict=False))
        return paths

    if git_root is None:
        raise RuntimeError(
            "project root is not inside a git repository and no source repo was found; "
            "pass --changed-file to supply the change set explicitly or set CODEGUIDE_SOURCE_ROOT"
        )

    # --no-renames so a renamed source shows BOTH its old and new path, otherwise a
    # doc that declares the old path would silently drop out of the change set.
    if args.range:
        rels = git_lines(["diff", "--name-only", "--no-renames", args.range], git_root)
    elif git_ok(["rev-parse", "--verify", "--quiet", "HEAD"], git_root):
        rels = git_lines(["diff", "--name-only", "--no-renames", "HEAD"], git_root)
        rels += git_lines(["ls-files", "--others", "--exclude-standard"], git_root)
    else:
        # Unborn HEAD (fresh repo, no commits yet): everything is staged or untracked.
        rels = git_lines(["diff", "--cached", "--name-only", "--no-renames"], git_root)
        rels += git_lines(["ls-files", "--others", "--exclude-standard"], git_root)

    for rel in rels:
        paths.add((git_root / rel).resolve(strict=False))
    return paths


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Read-only shadow impact report.")
    parser.add_argument("--project-root", required=True, help="Project root (git-root resolved).")
    parser.add_argument("--range", help="git range, e.g. main...HEAD.")
    parser.add_argument("--changed-file", action="append", help="Explicit changed path (repeatable).")
    parser.add_argument("--exit-code", action="store_true", help="Exit 1 if any impacted shadow doc was not refreshed.")
    args = parser.parse_args(argv)
    if args.range and args.changed_file:
        parser.error("--range and --changed-file are mutually exclusive")

    project_root = project_root_from(args.project_root)
    # Change sets come from the SOURCE repo, not the docs root: in the skills
    # layout the docs root may be a docs-only local repo whose diff never shows
    # source changes, which would make every impact report vacuously clean.
    git_root = source_root_for(project_root)
    shadow_dir = project_root / "docs" / "shadow"

    if not shadow_dir.is_dir():
        print(f"no shadow dir at {shadow_dir}; nothing to report")
        return 0

    try:
        changed = changed_abs_paths(args, project_root, git_root)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    # In the split-root layout shadow docs live in the DOCS repo while the
    # change set comes from the SOURCE repo, so "refreshed alongside sources"
    # could never match a doc path and every impacted doc would falsely hard-
    # fail --exit-code forever. Track docs-repo working-tree changes separately
    # for refresh detection (same-repo layouts keep the original single set).
    docs_changed: set[Path] = set()
    refresh_detectable = True
    docs_git_root = _git_toplevel(project_root)
    if docs_git_root is None and not args.changed_file:
        # Split-root layout whose docs root is untracked: the git-derived
        # change set cannot contain any docs path, so the binary refreshed/
        # needs-refresh classification would be permanently, misleadingly
        # false. Downgrade to an explicit third status instead.
        refresh_detectable = False
        print(
            f"warning: docs root {project_root} is not inside a git repository; "
            "refresh detection is unavailable — track the docs root in git or pass --changed-file",
            file=sys.stderr,
        )
    if docs_git_root is not None and docs_git_root != git_root:
        try:
            if git_ok(["rev-parse", "--verify", "--quiet", "HEAD"], docs_git_root):
                docs_rels = git_lines(["diff", "--name-only", "--no-renames", "HEAD"], docs_git_root)
            else:
                docs_rels = git_lines(["diff", "--cached", "--name-only", "--no-renames"], docs_git_root)
            docs_rels += git_lines(["ls-files", "--others", "--exclude-standard"], docs_git_root)
        except RuntimeError:
            docs_rels = []
        for rel in docs_rels:
            docs_changed.add((docs_git_root / rel).resolve(strict=False))

    impacted: list[tuple[str, list[str], bool | None]] = []
    for doc in sorted(shadow_dir.rglob("*.md")):
        rel_parts = doc.relative_to(shadow_dir).parts
        if rel_parts and rel_parts[0] in ("_deprecated", "_obsolete"):
            continue
        try:
            lines = doc.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        declared = read_source_paths(lines)
        if not declared:
            continue
        changed_sources = []
        for rel in declared:
            candidate = Path(rel)
            target = candidate if candidate.is_absolute() else (project_root / candidate)
            if target.resolve(strict=False) in changed:
                changed_sources.append(rel)
        if not changed_sources:
            continue
        doc_resolved = doc.resolve(strict=False)
        refreshed: bool | None = doc_resolved in changed or doc_resolved in docs_changed
        if not refreshed and not refresh_detectable:
            refreshed = None
        try:
            doc_label = str(doc.resolve(strict=False).relative_to(project_root))
        except ValueError:
            doc_label = str(doc)
        impacted.append((doc_label, changed_sources, refreshed))

    need_refresh = [item for item in impacted if item[2] is False]
    refresh_unknown = [item for item in impacted if item[2] is None]

    print("# Shadow Impact Report")
    print(f"- changed_files: {len(changed)}")
    print(f"- impacted_shadow_docs: {len(impacted)}")
    print(f"- need_refresh: {len(need_refresh)}")
    if refresh_unknown:
        print(f"- refresh_unknown: {len(refresh_unknown)}")
    if not impacted:
        print("- result: no shadow doc declares any changed source")
    for doc_label, changed_sources, refreshed in impacted:
        if refreshed:
            print(f"- ok (refreshed alongside sources): {doc_label}")
        elif refreshed is None:
            print(
                f"- impact detected, refresh state unknown (docs root not git-tracked): {doc_label} "
                f"declares changed source(s): {', '.join(changed_sources)}"
            )
        else:
            print(f"- NEEDS REFRESH: {doc_label} declares changed source(s) but was not refreshed: {', '.join(changed_sources)}")

    if args.exit_code and need_refresh:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
