#!/usr/bin/env python3
"""Read-only shadow metrics report.

Quantifies the shadow layer so "token-wasting duplication" is a measurement rather
than a vibe: the estimated token cost of the always-read layer (router + _global +
bucket indexes), each doc's size against the anti-dump targets (~200 preferred,
<=300 cap), and how routing-oriented (vs source-mirroring) each doc is.

READ-ONLY and deterministic: it only reads and prints. Token counts are an ESTIMATE
(characters / 4) since no tokenizer is guaranteed available. Routing-vs-prose is a
proxy: structured lines (headings, `- key:`/list items, tables, blockquotes) vs free
prose vs fenced code (the source-mirroring signal).

Exit code is 0 by default; --exit-code exits 1 when any doc exceeds the soft target.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import shadow_doc_parse  # DRY: one shared answer for what a fence is
try:
    from codeguide_paths import is_skill_package_root as _is_skill_package_root
except Exception:  # pragma: no cover
    _is_skill_package_root = None

BUCKETS = ("apps", "services", "packages", "infra", "data")
_routing_re = re.compile(r"^\s*(#{1,6}\s|-\s|\|| {0,3}>\s)")


def resolve_project_root(raw: str) -> Path:
    """Locate the root whose docs/shadow to measure.

    Uses the CLI root as-is when it already holds docs/shadow (normal repos and monorepo
    subprojects), and only falls back to the parent for a skill-package layout whose docs
    live one level up (this repo's own shape). It never collapses to the git top-level,
    which would break a subproject that keeps its own docs/shadow.
    """
    root = Path(raw).resolve(strict=False)
    if (root / "docs" / "shadow").is_dir():
        return root
    is_skill = _is_skill_package_root(root) if _is_skill_package_root else (root / "SKILL.md").is_file()
    if is_skill and not (root / "docs").is_dir():
        parent = root.parent
        if (parent / "docs" / "shadow").is_dir():
            return parent
    return root


def estimate_tokens(text: str) -> int:
    return round(len(text) / 4)


def _fence_marker(line: str) -> tuple[str, int] | None:
    """Return (char, run-length) if the line opens/closes a fenced block, else None.

    This reader had the CommonMark rule right before the others did; it now delegates
    so the correct behavior has exactly one home (the recorded decision).
    """
    return shadow_doc_parse.fence_marker(line)


def classify_lines(text: str) -> tuple[int, int, int]:
    """Return (routing, prose, code) non-blank line counts.

    A fenced block closes only on a same-character marker at least as long as the opener
    (CommonMark), so a nested 3-backtick line inside a 4-backtick block stays code and an
    unterminated fence runs to EOF.
    """
    routing = prose = code = 0
    fence_char: str | None = None
    fence_len = 0
    for line in shadow_doc_parse.split_lines(text):
        marker = _fence_marker(line)
        if fence_char is not None:
            if marker is not None and marker[0] == fence_char and marker[1] >= fence_len:
                fence_char = None
                fence_len = 0
                code += 1
            elif line.strip():
                code += 1
            continue
        if marker is not None:
            fence_char, fence_len = marker
            code += 1
            continue
        if not line.strip():
            continue
        if _routing_re.match(line):
            routing += 1
        else:
            prose += 1
    return routing, prose, code


def routing_pct(routing: int, prose: int, code: int) -> int:
    total = routing + prose + code
    return round(100 * routing / total) if total else 0


def iter_shadow_docs(shadow_dir: Path):
    for doc in sorted(shadow_dir.rglob("*.md")):
        rel_parts = doc.relative_to(shadow_dir).parts
        if rel_parts and rel_parts[0] in ("_deprecated", "_obsolete"):
            continue
        yield doc


def always_read_set(shadow_dir: Path) -> set[Path]:
    members = {shadow_dir / "project-shadow.md", shadow_dir / "_global.md"}
    for bucket in BUCKETS:
        members.add(shadow_dir / bucket / "_index.md")
    return {p.resolve(strict=False) for p in members}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Read-only shadow metrics report.")
    parser.add_argument("--project-root", required=True, help="Project root (docs/shadow lives here).")
    parser.add_argument("--soft-target", type=int, default=200, help="Preferred max lines per shadow doc (default 200).")
    parser.add_argument("--hard-cap", type=int, default=300, help="Hard max lines per shadow doc (default 300).")
    parser.add_argument("--top", type=int, default=15, help="How many largest docs to list (default 15; 0 = all).")
    parser.add_argument("--exit-code", action="store_true", help="Exit 1 if any doc exceeds the soft target.")
    args = parser.parse_args(argv)
    if args.soft_target > args.hard_cap:
        parser.error("--soft-target must be <= --hard-cap")

    project_root = resolve_project_root(args.project_root)
    shadow_dir = project_root / "docs" / "shadow"
    if not shadow_dir.is_dir():
        print(f"no shadow dir at {shadow_dir}; nothing to report")
        return 0

    always = always_read_set(shadow_dir)
    docs = []
    total_lines = total_tokens = 0
    always_lines = always_tokens = always_docs = 0
    r_sum = p_sum = c_sum = 0
    over_soft = []
    over_hard = []
    skipped = 0

    for doc in iter_shadow_docs(shadow_dir):
        try:
            # Byte-faithful: `Path.read_text` translates CRLF and a lone CR to `\n` before
            # any splitter sees them, which silently undid the shared line rule
            # `text.count("\n")` below is
            # what `wc -l` counts either way; what changes is that classify_lines now
            # answers on the same lines `grep` and `awk` do.
            text = shadow_doc_parse.read_document_text(doc)
        except OSError:
            skipped += 1
            continue
        # Count newlines only, to match validate_docs.sh check_line_limit (wc -l), so the
        # anti-dump flags here agree with the enforcing validator rather than over-reporting.
        lines = text.count("\n")
        tokens = estimate_tokens(text)
        routing, prose, code = classify_lines(text)
        try:
            label = str(doc.resolve(strict=False).relative_to(project_root))
        except ValueError:
            label = str(doc)
        docs.append((lines, tokens, routing, prose, code, label))
        total_lines += lines
        total_tokens += tokens
        r_sum += routing
        p_sum += prose
        c_sum += code
        if doc.resolve(strict=False) in always:
            always_docs += 1
            always_lines += lines
            always_tokens += tokens
        if lines > args.hard_cap:
            over_hard.append((label, lines))
        elif lines > args.soft_target:
            over_soft.append((label, lines))

    print("# Shadow Metrics Report")
    print(f"- shadow_docs: {len(docs)}")
    if skipped:
        print(f"- unreadable_skipped: {skipped}")
    print(f"- total_lines: {total_lines}")
    print(f"- total_est_tokens: ~{total_tokens}")
    print(f"- always_read_layer: {always_docs} docs, {always_lines} lines, ~{always_tokens} tokens")
    print(f"- routing_pct_overall: {routing_pct(r_sum, p_sum, c_sum)}%  (routing {r_sum} / prose {p_sum} / code {c_sum})")
    print(f"- over_soft_target(>{args.soft_target}): {len(over_soft) + len(over_hard)}")
    print(f"- over_hard_cap(>{args.hard_cap}): {len(over_hard)}")
    for label, lines in over_hard:
        print(f"  - OVER CAP: {label} ({lines} lines)")
    for label, lines in over_soft:
        print(f"  - over target: {label} ({lines} lines)")

    ranked = sorted(docs, reverse=True)
    shown = ranked if args.top == 0 else ranked[: args.top]
    if shown:
        print("## Largest docs")
    for lines, tokens, routing, prose, code, label in shown:
        print(f"- {label}: {lines} lines, ~{tokens} tokens, routing {routing_pct(routing, prose, code)}% (r {routing} / p {prose} / c {code})")

    if args.exit_code and (over_soft or over_hard):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
