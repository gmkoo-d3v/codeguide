#!/usr/bin/env python3
"""Read-only shadow rationale report and rationale-link linter.

Shadow docs declare the decisions that govern them in `linked_decisions` (see
references/shadow-system-contract.md). That edge is authored in the direction an
agent travels -- router -> bucket -> overview -> leaf -- because "why is this
shaped this way" is asked while standing on the shadow doc. This tool derives
the other views on demand instead of storing them as a backlink index.

Two modes over ONE parser:

  (default)  the human/agent report: five sections, always printed in a fixed
             order so two runs over the same corpus are byte-identical.
  --lint     tab-separated findings for `check_shadow_linked_decisions` in
             validate_docs.d/20-rules-shadow.sh, which turns them into
             fail/soft_warn lines. Same lineage as shadow_source_digest.py
             --check, and the reason the grammar cannot drift between the
             validator and the report: there is only one implementation of it.

Deterministic and READ-ONLY: it parses docs and prints; it never writes shadow
content, never edits a capsule, and never infers an edge from prose.

Exit codes: 0 for any completed run, findings included -- the validator owns the
pass/fail opinion, and a report that failed a build would duplicate that gate
with weaker context. 2 for usage and I/O errors (unreadable root, unreadable
doc), so a broken invocation can never be mistaken for a clean corpus.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # keep the tool read-only: no .pyc writes into scripts/
sys.path.insert(0, str(Path(__file__).resolve().parent))
from codeguide_paths import resolve_project_root  # DRY: same git-root/skill-parent resolution as the sibling reports

FIELD = "linked_decisions"
DECISION_DIR = "docs/decisions"
# decision-index.md is a ledger and decision-template.md is a blank: both match the
# filename shape but carry no rationale, so neither is a corpus member or a valid target.
NOT_A_CAPSULE = ("decision-index.md", "decision-template.md")
CARRIER_ROLES = ("unit_overview", "concern_leaf")
SKIP_TREES = ("_deprecated", "_obsolete")

_fence = chr(96) * 3
_tilde_fence = "~" * 3
_field_inline_re = re.compile(r"^\s*-\s*" + FIELD + r"\s*:\s*(\S.*?)\s*$")
_field_header_re = re.compile(r"^(\s*)-\s*" + FIELD + r"\s*:\s*$")
_bullet_re = re.compile(r"^(\s*)-\s+(\S.*?)\s*$")
_doc_role_re = re.compile(r"^\s*-\s*doc_role\s*:\s*(\S.*?)\s*$")
_status_re = re.compile(r"^\s*-\s*status\s*:\s*(\S.*?)\s*$")


class DocReadError(Exception):
    """A corpus file could not be read; callers turn this into exit 2."""


def content_lines(lines: list[str]):
    """Yield lines outside fenced blocks (backtick or tilde), mirroring extract_shadow_field."""
    in_fence = False
    for line in lines:
        stripped = line.lstrip()
        if stripped.startswith(_fence) or stripped.startswith(_tilde_fence):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        yield line


def first_field(lines: list[str], pattern: re.Pattern) -> str:
    """First non-empty value outside fences. A second occurrence is ignored by design."""
    for line in content_lines(lines):
        match = pattern.match(line)
        if match:
            return match.group(1).strip()
    return ""


def has_nested_form(lines: list[str]) -> bool:
    """True when a bare `linked_decisions:` header is followed by a deeper bullet.

    Only the bullets that actually follow the header count, and fenced examples are
    invisible: an unrelated indented bullet further down the doc must not be read
    as a member (the same binding rule the navigation-link scanner uses).
    """
    pending_indent = -1
    for line in content_lines(lines):
        if _field_inline_re.match(line):
            pending_indent = -1
            continue
        header = _field_header_re.match(line)
        if header:
            pending_indent = len(header.group(1))
            continue
        if pending_indent >= 0:
            bullet = _bullet_re.match(line)
            if bullet:
                if len(bullet.group(1)) > pending_indent:
                    return True
                pending_indent = -1
            elif line.strip():
                pending_indent = -1
    return False


def read_lines(path: Path) -> list[str]:
    try:
        return path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as exc:
        raise DocReadError(f"{path}: {exc}") from None


def shadow_docs(shadow_dir: Path) -> list[Path]:
    docs = []
    for doc in sorted(shadow_dir.rglob("*.md")):
        parts = doc.relative_to(shadow_dir).parts
        if parts and parts[0] in SKIP_TREES:
            continue
        docs.append(doc)
    return docs


def decision_capsules(decisions_dir: Path) -> list[Path]:
    if not decisions_dir.is_dir():
        return []
    return [
        capsule
        for capsule in sorted(decisions_dir.glob("decision-*.md"))
        if capsule.name not in NOT_A_CAPSULE
    ]


def label_for(path: Path, project_root: Path) -> str:
    try:
        return str(path.resolve(strict=False).relative_to(project_root))
    except ValueError:
        return str(path)


def scan(project_root: Path, shadow_dir: Path):
    """The single grammar implementation. Returns (declared, cited_by, findings).

    findings are (kind, doc_label, detail) tuples; `--lint` prints them verbatim and
    the report renders them as its Problems section, so the two modes can never
    disagree about what is malformed.
    """
    declared: list[tuple[str, list[tuple[str, str]]]] = []
    cited_by: dict[str, list[str]] = {}
    findings: list[tuple[str, str, str]] = []

    for doc in shadow_docs(shadow_dir):
        lines = read_lines(doc)
        doc_label = label_for(doc, project_root)
        raw = first_field(lines, _field_inline_re)

        if not raw:
            if has_nested_form(lines):
                findings.append(("nested", doc_label, ""))
            continue

        role = first_field(lines, _doc_role_re)
        if role not in CARRIER_ROLES:
            findings.append(("role", doc_label, role or "none"))
            continue

        resolved: list[tuple[str, str]] = []
        seen: set[str] = set()
        for entry in (part.strip() for part in raw.split(",")):
            if not entry:
                findings.append(("empty", doc_label, ""))
                continue
            if entry in seen:
                findings.append(("duplicate", doc_label, entry))
                continue
            seen.add(entry)

            name = entry.rsplit("/", 1)[-1]
            if name in NOT_A_CAPSULE:
                findings.append(("not_capsule", doc_label, entry))
                continue
            # Exact shape: docs/decisions/decision-<id>.md, no traversal, no nesting.
            if entry != f"{DECISION_DIR}/{name}" or not name.startswith("decision-") or not name.endswith(".md"):
                findings.append(("shape", doc_label, entry))
                continue

            target = project_root / entry
            if not target.is_file():
                findings.append(("dangling", doc_label, entry))
                continue

            status = first_field(read_lines(target), _status_re)
            if status == "accepted":
                pass
            elif status == "superseded":
                findings.append(("superseded", doc_label, entry))
            elif status == "proposed":
                findings.append(("proposed", doc_label, entry))
            else:
                findings.append(("no_status", doc_label, entry))

            resolved.append((entry, status or "unknown"))
            cited_by.setdefault(entry, []).append(doc_label)

        if resolved:
            declared.append((doc_label, sorted(resolved)))

    return declared, cited_by, findings


FINDING_TEXT = {
    "nested": lambda detail: "must be an inline comma list, not nested bullets",
    "role": lambda detail: f"{FIELD} on doc_role={detail} (only {'/'.join(CARRIER_ROLES)} carry rationale)",
    "empty": lambda detail: f"empty {FIELD} member",
    "duplicate": lambda detail: f"duplicate entry {detail}",
    "not_capsule": lambda detail: f"{detail} is not a decision capsule (index/template carry no rationale)",
    "shape": lambda detail: f"{detail} is not a repo-relative {DECISION_DIR}/decision-<id>.md path",
    "dangling": lambda detail: f"{detail} does not resolve",
    "superseded": lambda detail: f"{detail} is superseded; link the successor",
    "proposed": lambda detail: f"{detail} is only proposed",
    "no_status": lambda detail: f"{detail} has no readable status",
}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Read-only shadow rationale report.")
    parser.add_argument("--project-root", required=True, help="Project root (git-root resolved).")
    parser.add_argument(
        "--lint",
        action="store_true",
        help="Emit tab-separated findings (kind, doc, detail) for the docs validator instead of the report.",
    )
    args = parser.parse_args(argv)

    root_input = Path(args.project_root)
    if not root_input.exists():
        print(f"error: project root does not exist: {root_input}", file=sys.stderr)
        return 2
    try:
        project_root = resolve_project_root(root_input)
    except OSError as exc:
        print(f"error: could not resolve project root: {exc}", file=sys.stderr)
        return 2

    shadow_dir = project_root / "docs" / "shadow"
    decisions_dir = project_root / DECISION_DIR

    if not shadow_dir.is_dir():
        if not args.lint:
            print(f"no shadow dir at {shadow_dir}; nothing to report")
        return 0

    try:
        declared, cited_by, findings = scan(project_root, shadow_dir)
        capsules = decision_capsules(decisions_dir)
        uncited = sorted(
            label_for(capsule, project_root)
            for capsule in capsules
            if first_field(read_lines(capsule), _status_re) == "accepted"
            and label_for(capsule, project_root) not in cited_by
        )
    except DocReadError as exc:
        print(f"error: could not read a corpus document: {exc}", file=sys.stderr)
        return 2

    if args.lint:
        # Leading summary record: the validator needs "is the field in use at all"
        # to decide whether a clean corpus deserves a PASS line, and deriving that
        # from a grep would reintroduce the fence-blindness this mode exists to end.
        # The count goes in the SECOND field, not the third: TAB is an IFS
        # whitespace character, so `read -r a b c` collapses a run of tabs and an
        # empty middle field would silently shift the value into `b`.
        print(f"declared\t{len(declared)}")
        for kind, doc_label, detail in sorted(findings):
            print(f"{kind}\t{doc_label}\t{detail}")
        return 0

    problems = sorted(
        f"{doc_label}: {FINDING_TEXT[kind](detail)}"
        for kind, doc_label, detail in findings
        if kind != "proposed"
    )
    notes = sorted(
        f"{doc_label}: {FINDING_TEXT[kind](detail)}"
        for kind, doc_label, detail in findings
        if kind == "proposed"
    )

    print("# Shadow Rationale Report")
    print(f"- shadow_docs_with_rationale: {len(declared)}")
    print(f"- decisions_cited: {len(cited_by)}")
    print(f"- accepted_decisions_uncited: {len(uncited)}")
    print(f"- problems: {len(problems)}")
    print(f"- notes: {len(notes)}")

    # Every section is printed unconditionally and in a fixed order: an absent
    # heading would make "nothing to report" indistinguishable from a parse that
    # never reached the section.
    print("## Shadow doc -> decisions")
    for doc_label, entries in sorted(declared):
        rendered = ", ".join(f"{entry} [{status}]" for entry, status in entries)
        print(f"- {doc_label}: {rendered}")

    print("## Decision -> citing shadow docs")
    for entry in sorted(cited_by):
        print(f"- {entry}: {', '.join(sorted(cited_by[entry]))}")

    print("## Accepted decisions no shadow doc cites")
    for capsule_label in uncited:
        print(f"- {capsule_label}")

    print("## Problems")
    for problem in problems:
        print(f"- {problem}")

    print("## Notes")
    for note in notes:
        print(f"- {note}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
