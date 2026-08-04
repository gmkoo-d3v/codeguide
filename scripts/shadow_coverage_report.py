#!/usr/bin/env python3
"""Read-only shadow coverage report.

The sibling to shadow_impact_report.py. The impact report asks "I changed X and did
I REFRESH the shadow doc for it?"; this asks "I changed X and does ANY shadow doc
DOCUMENT it at all?" It reports changed source files that no shadow doc references in
its `source_of_truth_paths` -- the under-documentation gap.

Deterministic and READ-ONLY: no writes, no auto-generation of shadow docs. It only
reports coverage, driven by a real change set (not by heuristic unit-guessing), which
keeps the noise low.

Change-set sources (same as shadow_impact_report.py):
  --range <git-range>       Files changed in a git range.
  --changed-file <path>     Explicit source path (repeatable).
  (default)                 Working tree: tracked changes vs HEAD plus untracked files.

A changed source S is COVERED if any declared source path D across all shadow docs
overlaps it: D == S, or D is an ancestor of S, or S is an ancestor of D (so a doc that
declares a directory covers files under it, and vice-versa). Paths under docs/ are not
treated as source. Exit 0 by default; --exit-code exits 1 when any source is uncovered.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from codeguide_paths import source_root_for  # DRY: shared source-repo resolution policy
from shadow_source_digest import source_paths_for_doc  # DRY: same parser AND the same line rule as the digest tool
from shadow_impact_report import (  # DRY: same change-set derivation as the impact report
    changed_abs_paths,
    project_root_from,
)


def declared_source_paths(shadow_dir: Path, project_root: Path) -> set[Path]:
    declared: set[Path] = set()
    if not shadow_dir.is_dir():
        return declared
    for doc in shadow_dir.rglob("*.md"):
        rel_parts = doc.relative_to(shadow_dir).parts
        if rel_parts and rel_parts[0] in ("_deprecated", "_obsolete"):
            continue
        try:
            declared_paths = source_paths_for_doc(doc)
        except OSError:
            continue
        for rel in declared_paths:
            candidate = Path(rel)
            target = candidate if candidate.is_absolute() else (project_root / candidate)
            try:
                resolved = target.resolve(strict=False)
            except (OSError, ValueError):
                continue  # malformed declared path (e.g. embedded NUL); ignore for coverage
            # Only bounded, in-project declarations count as coverage. This drops a
            # blanket "." (== project_root) and any escaping ../ or absolute-outside path,
            # so one over-broad declaration cannot silently "cover" the whole project.
            if project_root in resolved.parents:
                declared.add(resolved)
    return declared


def is_covered(source: Path, declared: set[Path]) -> bool:
    # Set lookups keep the common (file source) case O(path depth) instead of O(declared).
    if source in declared:
        return True
    if any(parent in declared for parent in source.parents):
        return True
    # A directory source is covered if any declared path lives under it. Only dirs pay
    # this O(declared) scan; file sources cannot be an ancestor of anything.
    if source.is_dir() and any(source in decl.parents for decl in declared):
        return True
    return False


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Read-only shadow coverage report.")
    parser.add_argument("--project-root", required=True, help="Project root (docs/shadow lives here).")
    parser.add_argument("--range", help="git range, e.g. main...HEAD.")
    parser.add_argument("--changed-file", action="append", help="Explicit source path (repeatable).")
    parser.add_argument("--exit-code", action="store_true", help="Exit 1 if any changed source is uncovered.")
    args = parser.parse_args(argv)
    if args.range and args.changed_file:
        parser.error("--range and --changed-file are mutually exclusive")

    project_root = project_root_from(args.project_root)
    # Same policy as the impact report: derive the change set from the source
    # repo, never from a docs-only local repo at the project root.
    git_root = source_root_for(project_root)
    shadow_dir = project_root / "docs" / "shadow"
    docs_dir = project_root / "docs"

    try:
        changed = changed_abs_paths(args, project_root, git_root)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    declared = declared_source_paths(shadow_dir, project_root)

    uncovered: list[str] = []
    considered = 0
    for source in sorted(changed):
        # Skip deleted paths (nothing left to document).
        if not source.exists():
            continue
        # Scope coverage to THIS project: a change elsewhere in the same git repo (e.g. a
        # sibling monorepo subproject outside project_root) is not this project's concern.
        if source != project_root and project_root not in source.parents:
            continue
        # docs are not source.
        if source == docs_dir or docs_dir in source.parents:
            continue
        considered += 1
        if not is_covered(source, declared):
            uncovered.append(str(source.relative_to(project_root)))

    print("# Shadow Coverage Report")
    print(f"- changed_source_files: {considered}")
    print(f"- shadow_declared_sources: {len(declared)}")
    print(f"- uncovered: {len(uncovered)}")
    if considered == 0:
        print("- result: no changed source files to check")
    for path in uncovered:
        print(f"- UNCOVERED: {path} is not referenced by any shadow doc's source_of_truth_paths")
    if not uncovered and considered:
        print("- result: every changed source is documented by a shadow doc")

    if args.exit_code and uncovered:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
