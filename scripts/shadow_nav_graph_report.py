#!/usr/bin/env python3
"""Read-only shadow navigation graph report.

Item 1 checks the FORWARD direction of the read path (do nav references resolve to
real files?). This checks the BACKWARD direction: starting at the router
(project-shadow.md) and following resolved nav edges (bucket_links -> overview_doc ->
next_docs), is every value-carrier doc reachable? A unit_overview or concern_leaf that
exists but that nothing links to is an ORPHAN -- an agent walking the read path never
finds it. It also reports the hop depth to reach each doc.

Deterministic and READ-ONLY: pure graph traversal, no writes, no inference. Intentional
side-paths (_global, effect_map, review_queue, redirect_shim) are not orphan-eligible;
only unit_overview and concern_leaf are. Exit 0 by default; --exit-code exits 1 when any
orphan exists (a real navigation break).
"""
from __future__ import annotations

import argparse
import re
import sys
from collections import deque
from pathlib import Path

sys.dont_write_bytecode = True  # keep the tool read-only: no .pyc writes into scripts/ on import
sys.path.insert(0, str(Path(__file__).resolve().parent))
from codeguide_paths import resolve_project_root  # DRY: same git-root/skill-parent resolution as item 1
import shadow_doc_parse  # DRY: one shared answer for fences and field values

# canonical_path is included for parity with the item-1 link check: a router-reachable
# redirect_shim redirects to the canonical carrier via canonical_path, so it is a real edge.
NAV_FIELDS = ("bucket_links", "global_doc", "overview_doc", "next_docs", "canonical_path")
ORPHAN_ELIGIBLE = ("bucket_index", "unit_overview", "concern_leaf")
RECOGNIZED_ROLES = {
    "router", "global", "bucket_index", "unit_overview", "concern_leaf",
    "effect_map", "review_queue", "redirect_shim",
}
_inline_re = re.compile(r"^(\s*)-\s*(" + "|".join(NAV_FIELDS) + r")\s*:\s*(\S.*?)\s*$")
_header_re = re.compile(r"^(\s*)-\s*(" + "|".join(NAV_FIELDS) + r")\s*:\s*$")
_bullet_re = re.compile(r"^(\s*)-\s+(.*?)\s*$")
_doc_role_re = re.compile(r"^\s*-\s*doc_role\s*:\s*(\S.*?)\s*$")
# A doc token is a run of path characters ending in .md; the restricted class stops the
# greedy match at Markdown-link punctuation (same rule as the item-1 link check).
_token_re = re.compile(r"[A-Za-z0-9._/-]+\.md\b")


def _content_lines(lines: list[str]):
    # Shared with the validator so a report and a gate cannot disagree about
    # whether a line is inside a fence.
    return shadow_doc_parse.content_lines(lines)


def doc_role_of(lines: list[str]) -> str:
    for line in _content_lines(lines):
        match = _doc_role_re.match(line)
        if match:
            return match.group(1).strip()
    return ""


def nav_tokens(lines: list[str]) -> list[tuple[str, str]]:
    """Return (field, token) for nav references outside fenced blocks (inline + nested).

    Fence boundaries reset the pending nested-field state (mirroring the item-1 link
    check), so a bullet after a fenced example is never mis-attributed to a field header
    that appeared before the fence.
    """
    tokens: list[tuple[str, str]] = []
    pending: str | None = None
    pending_indent = -1
    for kind, line in shadow_doc_parse.scan(lines):
        if kind == "boundary":
            pending = None
            continue
        inline = _inline_re.match(line)
        if inline:
            pending = None
            tokens.extend((inline.group(2), t) for t in _token_re.findall(inline.group(3)))
            continue
        header = _header_re.match(line)
        if header:
            pending = header.group(2)
            pending_indent = len(header.group(1))
            continue
        if pending is not None:
            bullet = _bullet_re.match(line)
            if bullet and len(bullet.group(1)) > pending_indent:
                tokens.extend((pending, t) for t in _token_re.findall(bullet.group(2)))
                continue
            if line.strip():
                pending = None
    return tokens


def resolve_token(token: str, ref_file: Path, project_root: Path, shadow_dir: Path) -> Path | None:
    candidate = Path(token)
    if candidate.is_absolute():
        try:
            resolved = candidate.resolve(strict=False)
        except (OSError, ValueError):
            return None
        return resolved if resolved.is_file() else None
    # Same precise bases as the item-1 link check: docs/-prefixed refs are project-root
    # relative; every other shadow ref resolves against the shadow root or the ref's dir.
    bases = (project_root,) if token.startswith("docs/") else (shadow_dir, ref_file.parent)
    for base in bases:
        try:
            resolved = (base / candidate).resolve(strict=False)
        except (OSError, ValueError):
            continue
        if resolved.is_file():
            return resolved
    return None


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Read-only shadow navigation graph report.")
    parser.add_argument("--project-root", required=True, help="Project root (docs/shadow lives here).")
    parser.add_argument("--top", type=int, default=15, help="How many deepest docs to list (default 15; 0 = all).")
    parser.add_argument("--exit-code", action="store_true", help="Exit 1 if any value-carrier doc is orphaned.")
    args = parser.parse_args(argv)

    project_root = resolve_project_root(Path(args.project_root))
    shadow_dir = project_root / "docs" / "shadow"
    if not shadow_dir.is_dir():
        print(f"no shadow dir at {shadow_dir}; nothing to report")
        return 0

    nodes: dict[Path, tuple[str, list[str]]] = {}
    for doc in sorted(shadow_dir.rglob("*.md")):
        rel_parts = doc.relative_to(shadow_dir).parts
        if rel_parts and rel_parts[0] in ("_deprecated", "_obsolete"):
            continue
        try:
            lines = shadow_doc_parse.read_lines(doc)
        except OSError:
            continue
        nodes[doc.resolve(strict=False)] = (doc_role_of(lines), lines)

    adjacency: dict[Path, set[Path]] = {node: set() for node in nodes}
    for node, (_role, lines) in nodes.items():
        for _field, token in nav_tokens(lines):
            target = resolve_token(token, node, project_root, shadow_dir)
            if target is not None and target in nodes and target != node:
                adjacency[node].add(target)

    root = (shadow_dir / "project-shadow.md").resolve(strict=False)
    distance: dict[Path, int] = {}
    if root in nodes:
        distance[root] = 0
        queue = deque([root])
        while queue:
            current = queue.popleft()
            for neighbour in sorted(adjacency[current]):
                if neighbour not in distance:
                    distance[neighbour] = distance[current] + 1
                    queue.append(neighbour)

    def label(path: Path) -> str:
        try:
            return str(path.relative_to(project_root))
        except ValueError:
            return str(path)

    orphans = sorted(
        label(node)
        for node, (role, _lines) in nodes.items()
        if role in ORPHAN_ELIGIBLE and node not in distance
    )
    # Surface docs whose doc_role is missing or unrecognized -- a typo'd carrier role
    # would otherwise be silently excluded from orphan detection.
    unclassified = sorted(
        label(node)
        for node, (role, _lines) in nodes.items()
        if role not in RECOGNIZED_ROLES
    )
    depths = [d for d in distance.values()]
    max_depth = max(depths) if depths else 0
    avg_depth = round(sum(depths) / len(depths), 1) if depths else 0

    print("# Shadow Navigation Graph Report")
    print(f"- shadow_docs: {len(nodes)}")
    print(f"- router_present: {'yes' if root in nodes else 'no'}")
    print(f"- reachable_from_router: {len(distance)}")
    print(f"- orphans: {len(orphans)}")
    print(f"- unclassified: {len(unclassified)}")
    print(f"- max_depth: {max_depth} hops, avg_depth: {avg_depth}")
    if root not in nodes:
        print("- note: project-shadow.md router is missing; reachability could not be computed")
    for orphan in orphans:
        print(f"- ORPHAN: {orphan} (value-carrier doc not reachable from the router read path)")
    for doc in unclassified:
        print(f"- UNCLASSIFIED: {doc} (missing or unrecognized doc_role; not orphan-checked)")

    ranked = sorted(((d, label(n)) for n, d in distance.items()), reverse=True)
    shown = ranked if args.top == 0 else ranked[: args.top]
    if shown:
        print("## Deepest reachable docs")
    for depth, name in shown:
        print(f"- {name}: {depth} hops")

    if args.exit_code and orphans:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
