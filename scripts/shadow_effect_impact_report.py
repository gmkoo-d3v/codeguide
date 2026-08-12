#!/usr/bin/env python3
"""Read-only shadow effect impact report.

Given the set of changed source files (a git range, the working tree, or an
explicit --changed-file list) and the effect_map docs under docs/shadow, report
two facts and nothing else:

  re-verify:      a CONFIRMED effect record's anchor file is in the change set.
                  The anchor may now contradict its evidence; a human or a
                  deterministic evidence rerun must decide.
  anchor-missing: an effect record declares an anchor file that does not exist
                  on disk.

This tool is deterministic and READ-ONLY. It never writes shadow content, never
modifies effect_map docs, and NEVER auto-decides invalidation (decision
The task): both facts only raise a flag that a human or a
later deterministic step must act on.

Change-set sources (pick one):
  --range <git-range>       Files changed in a git range, e.g. main...HEAD or HEAD~1..HEAD.
  --changed-file <path>     Explicit changed path (repeatable); project-root relative or absolute.
  (default)                 Working tree: tracked changes vs HEAD plus untracked files.

Exit code is 0 by default (a report). With --exit-code it exits 1 when at least
one flag (re-verify or anchor-missing) was emitted. Git failure exits 2.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from codeguide_paths import source_root_for  # DRY: shared source-repo resolution policy
from shadow_doc_parse import field_value, read_document_text, split_lines  # DRY: shared line and field rules
from shadow_impact_report import changed_abs_paths, project_root_from  # DRY: change-set computation and root policy

# Marker line and record-id charset are the writer's (shadow_effect_writer.py);
# the anchored shape is the validator's (validate_docs.d/20-rules-shadow.sh).
MARKER_RE = re.compile(r"<!--\s*shadow-effect-record:([A-Za-z0-9_.:-]{3,120})\s+(begin|end)\s*-->")
FIELD_RE = re.compile(r"^\s*-\s*([A-Za-z0-9_]+)\s*:\s*(.*?)\s*$")
SKIPPED_DIRS = ("_deprecated", "_obsolete")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Read-only shadow effect impact report.")
    parser.add_argument("--project-root", required=True, help="Project root (docs/shadow lives under it).")
    parser.add_argument("--range", help="git range, e.g. main...HEAD.")
    parser.add_argument("--changed-file", action="append", help="Explicit changed path (repeatable).")
    parser.add_argument("--exit-code", action="store_true", help="Exit 1 if any re-verify or anchor-missing flag was emitted.")
    args = parser.parse_args(argv)
    if args.range and args.changed_file:
        parser.error("--range and --changed-file are mutually exclusive")
    return args


def effect_map_docs(project_root: Path) -> list[tuple[Path, str]]:
    """Effect-map docs under <root>/docs/shadow, mirroring validate_docs.sh dispatch.

    Same enumeration as validate_docs.sh:375-385: every *.md under docs/shadow
    outside _deprecated/_obsolete whose content declares `doc_role: effect_map`.
    Each entry carries the doc's already-read text so callers do not re-read it.
    """
    shadow_dir = project_root / "docs" / "shadow"
    docs: list[tuple[Path, str]] = []
    if not shadow_dir.is_dir():
        return docs
    for doc in sorted(shadow_dir.rglob("*.md")):
        rel_parts = doc.relative_to(shadow_dir).parts
        if rel_parts and rel_parts[0] in SKIPPED_DIRS:
            continue
        try:
            text = read_document_text(doc)
        except OSError:
            continue
        if field_value(split_lines(text), "doc_role") != "effect_map":
            continue
        docs.append((doc, text))
    return docs


def _parse_field_lines(lines: list[str]) -> dict[str, str]:
    record: dict[str, str] = {}
    for line in lines:
        match = FIELD_RE.match(line)
        if match is not None:
            record[match.group(1)] = match.group(2).strip()
    return record


def parse_records(doc_text: str) -> list[dict[str, str]]:
    """Records between `<!-- shadow-effect-record:<id> begin -->`/`end -->` marker pairs.

    Inside a pair, every `- key: value` line becomes an entry. The marker id
    pairs begin/end only; a `- record_id:` field wins, the marker id is the
    fallback. Malformed markers are the validator's job; the reporter tolerates
    them and reports what it can.
    """
    records: list[dict[str, str]] = []
    current_id: str | None = None
    block: list[str] = []
    for line in split_lines(doc_text):
        marker = MARKER_RE.search(line)
        if marker is not None:
            rid, edge = marker.group(1), marker.group(2)
            if edge == "begin":
                current_id, block = rid, []
            elif edge == "end" and rid == current_id:
                record = _parse_field_lines(block)
                record.setdefault("record_id", rid)
                records.append(record)
                current_id, block = None, []
            continue
        if current_id is not None:
            block.append(line)
    return records


def normalized_anchor(project_root: Path, anchor_file: str) -> Path:
    """Project-root-relative anchor path, normalized like the validator's `normalized_path`.

    The single normalization point: the same Path feeds both the change-set
    membership check and the on-disk existence check.
    """
    raw = Path(anchor_file)
    if not raw.is_absolute():
        raw = project_root / raw
    return raw.resolve(strict=False)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    project_root = project_root_from(args.project_root)
    git_root = source_root_for(project_root)

    try:
        change_set = changed_abs_paths(args, project_root, git_root)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    re_verify: list[str] = []
    anchor_missing: list[str] = []
    for doc, text in effect_map_docs(project_root):
        try:
            doc_rel = str(doc.resolve(strict=False).relative_to(project_root))
        except ValueError:
            doc_rel = str(doc)
        for record in parse_records(text):
            lifecycle = record.get("lifecycle", "")
            anchor_file = record.get("anchor_file", "")
            record_id = record.get("record_id", "")
            if not anchor_file:
                continue
            anchor = normalized_anchor(project_root, anchor_file)
            if lifecycle == "confirmed" and anchor in change_set:
                re_verify.append(
                    f"re-verify: {doc_rel} record {record_id} (lifecycle confirmed) — anchor {anchor_file} is in the change set; "
                    "human or deterministic evidence decision required"
                )
            if not anchor.is_file():
                anchor_missing.append(
                    f"anchor-missing: {doc_rel} record {record_id} (lifecycle {lifecycle}) — anchor {anchor_file} does not exist"
                )

    print("# Shadow Effect Impact Report")
    for line in re_verify:
        print(line)
    for line in anchor_missing:
        print(line)
    print(f"summary: {len(re_verify)} re-verify, {len(anchor_missing)} anchor-missing")

    if args.exit_code and (re_verify or anchor_missing):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
