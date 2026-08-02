#!/usr/bin/env python3
"""Deterministic source-of-truth digest for a shadow doc.

A shadow navigation/concern doc may declare `source_of_truth_paths` (the source
files it summarizes). This tool binds the doc to the CONTENT of those files via a
`source_of_truth_digest` field, so freshness can be checked against what the source
actually is rather than a timestamp (which doc_garden auto-bumps).

The digest is a deliberate verification assertion: it must only be (re)written by an
explicit `--write` here, never auto-stamped by doc_garden or the scaffold. This is
the single source of truth for the digest algorithm; the validator calls `--check`.

Digest = sha256 over the newline-joined, sorted list of "<rel_path> <state>", where
<state> is "sha256:<hex>" for a readable in-project file, "MISSING" for a declared
path that does not resolve to a file, and "ESCAPED" for a path that resolves outside
the project root (absolute, `..`, or symlink escape). Sorting makes it order
independent; the MISSING/ESCAPED markers make a deleted or out-of-tree source produce
drift rather than a silently valid digest.

Modes:
  --emit   Print the current digest computed from source_of_truth_paths.
  --write  Upsert the source_of_truth_digest field (refuses if any source is
           missing or escapes the project root).
  --check  Compare recorded vs current digest; print a status block for the validator.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import shadow_doc_parse  # DRY: one shared answer for what a fence is
try:  # Reuse the repo's git-root resolution so --write and the validator agree.
    from codeguide_paths import resolve_project_root as _resolve_project_root
except Exception:  # pragma: no cover - fallback when import is unavailable
    _resolve_project_root = None

PATHS_FIELD = "source_of_truth_paths"
DIGEST_FIELD = "source_of_truth_digest"

_paths_field_re = re.compile(r"^(\s*)-\s*" + PATHS_FIELD + r"\s*:\s*(.*?)\s*$")
_digest_field_re = re.compile(r"^(\s*)-\s*" + DIGEST_FIELD + r"\s*:\s*(.*?)\s*$")
_bullet_re = re.compile(r"^(\s*)-\s+(.*?)\s*$")


def content_lines(lines: list[str]):
    """Yield (index, line) for lines outside fenced code blocks.

    Fence state is computed with the shared marker rule so this reader cannot
    disagree with the validator about what a fence is, and so a `~~~` marker inside
    a ``` block does not flip the state (the recorded decision).
    """
    open_char = None
    open_len = 0
    for index, line in enumerate(lines):
        marker = shadow_doc_parse.fence_marker(line)
        if open_char is None:
            if marker is not None:
                open_char, open_len = marker
                continue
            yield index, line
            continue
        if marker is not None and marker[0] == open_char and marker[1] >= open_len:
            open_char, open_len = None, 0


def _split_values(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def read_source_paths(lines: list[str]) -> list[str]:
    """Collect source_of_truth_paths from inline, nested-bullet, and mixed forms."""
    paths: list[str] = []
    pending = False
    pending_indent = -1
    for _, line in content_lines(lines):
        field = _paths_field_re.match(line)
        if field:
            pending = True
            pending_indent = len(field.group(1))
            paths.extend(_split_values(field.group(2)))  # inline value, if any
            continue
        if pending:
            bullet = _bullet_re.match(line)
            if bullet and len(bullet.group(1)) > pending_indent:
                paths.extend(_split_values(bullet.group(2)))  # nested value(s)
                continue
            if line.strip():
                pending = False
    seen: set[str] = set()
    unique: list[str] = []
    for path in paths:
        if path not in seen:
            seen.add(path)
            unique.append(path)
    return unique


def paths_block_end(lines: list[str]) -> int | None:
    """Index just after the last source_of_truth_paths block (header + nested bullets)."""
    end: int | None = None
    pending = False
    pending_indent = -1
    for index, line in content_lines(lines):
        field = _paths_field_re.match(line)
        if field:
            pending = True
            pending_indent = len(field.group(1))
            end = index + 1
            continue
        if pending:
            bullet = _bullet_re.match(line)
            if bullet and len(bullet.group(1)) > pending_indent:
                end = index + 1
                continue
            if line.strip():
                pending = False
    return end


def read_recorded_digest(lines: list[str]) -> str | None:
    for _, line in content_lines(lines):
        match = _digest_field_re.match(line)
        if match and match.group(2):
            return match.group(2).strip()
    return None


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def classify(rel: str, project_root: Path) -> tuple[str, str | None]:
    """Return ('ok', sha) | ('missing', None) | ('escaped', None)."""
    candidate = Path(rel)
    target = candidate if candidate.is_absolute() else (project_root / candidate)
    try:
        resolved = target.resolve(strict=True)
    except (OSError, ValueError):
        # ValueError covers malformed paths (e.g. an embedded NUL byte) so a bad
        # declared path is reported as missing rather than crashing the caller.
        return "missing", None
    if not resolved.is_file():
        return "missing", None
    try:
        resolved.relative_to(project_root)
    except ValueError:
        return "escaped", None
    return "ok", sha256_file(resolved)


def compute(doc: Path, project_root: Path) -> tuple[str | None, list[str], list[str], list[str]]:
    """Return (digest, declared, missing, escaped). digest is None if nothing is declared."""
    lines = doc.read_text(encoding="utf-8", errors="replace").splitlines()
    declared = read_source_paths(lines)
    if not declared:
        return None, [], [], []
    entries: list[str] = []
    missing: list[str] = []
    escaped: list[str] = []
    for rel in declared:
        kind, sha = classify(rel, project_root)
        if kind == "ok":
            entries.append(f"{rel} {sha}")
        elif kind == "escaped":
            entries.append(f"{rel} ESCAPED")
            escaped.append(rel)
        else:
            entries.append(f"{rel} MISSING")
            missing.append(rel)
    combined = "\n".join(sorted(entries))
    overall = "sha256:" + hashlib.sha256(combined.encode("utf-8")).hexdigest()
    return overall, declared, missing, escaped


def upsert_digest_field(doc: Path, digest: str) -> None:
    lines = doc.read_text(encoding="utf-8", errors="replace").splitlines()
    new_line = f"- {DIGEST_FIELD}: {digest}"
    for index, line in content_lines(lines):
        if _digest_field_re.match(line):
            lines[index] = new_line
            doc.write_text("\n".join(lines) + "\n", encoding="utf-8")
            return
    insert_at = paths_block_end(lines)
    if insert_at is None:
        insert_at = len(lines)
    lines.insert(insert_at, new_line)
    doc.write_text("\n".join(lines) + "\n", encoding="utf-8")


def resolve_root(raw: str) -> Path:
    if _resolve_project_root is not None:
        try:
            return Path(str(_resolve_project_root(Path(raw)))).resolve(strict=False)
        except Exception:
            pass
    return Path(raw).resolve(strict=False)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Deterministic source-of-truth digest for a shadow doc.")
    parser.add_argument("doc", help="Path to the shadow Markdown doc.")
    parser.add_argument("--project-root", required=True, help="Root that source_of_truth_paths are relative to (git-root resolved).")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--emit", action="store_true", help="Print the current digest.")
    mode.add_argument("--write", action="store_true", help="Write the current digest into the doc (explicit verification assertion).")
    mode.add_argument("--check", action="store_true", help="Compare recorded vs current digest and print a status block.")
    mode.add_argument("--verify-paths", action="store_true", help="Report declared source paths that are missing or escape the project root (no digest required).")
    args = parser.parse_args(argv)

    doc = Path(args.doc)
    if not doc.is_file():
        print(f"error: doc not found: {doc}", file=sys.stderr)
        return 2
    project_root = resolve_root(args.project_root)

    digest, _declared, missing, escaped = compute(doc, project_root)

    if args.emit:
        if digest is None:
            print(f"error: {doc} declares no {PATHS_FIELD}", file=sys.stderr)
            return 2
        print(digest)
        return 0

    if args.write:
        if digest is None:
            print(f"error: {doc} declares no {PATHS_FIELD}; nothing to bind", file=sys.stderr)
            return 2
        if missing or escaped:
            print(
                f"error: refusing to write digest; unusable source(s) missing={missing} escaped={escaped}",
                file=sys.stderr,
            )
            return 2
        upsert_digest_field(doc, digest)
        print(digest)
        return 0

    if args.verify_paths:
        # Emit parser-backed field detection so the validator can decide whether a doc
        # has real (non-fenced, non-empty) paths/digest without a raw grep.
        lines = doc.read_text(encoding="utf-8", errors="replace").splitlines()
        has_digest = read_recorded_digest(lines) is not None
        print(f"has_paths: {'true' if digest is not None else 'false'}")
        print(f"has_digest: {'true' if has_digest else 'false'}")
        if digest is None:
            print("status: no_paths_declared")
            return 0
        for rel in missing:
            print(f"missing: {rel}")
        for rel in escaped:
            print(f"escaped: {rel}")
        print("status: problems" if (missing or escaped) else "status: ok")
        return 0

    # --check
    lines = doc.read_text(encoding="utf-8", errors="replace").splitlines()
    recorded = read_recorded_digest(lines)
    if recorded is None:
        print("status: no_digest")
        return 0
    if digest is None:
        print("status: no_paths")
        return 0
    for rel in missing:
        print(f"missing: {rel}")
    for rel in escaped:
        print(f"escaped: {rel}")
    if digest != recorded:
        print("status: drift")
        print(f"recorded: {recorded}")
        print(f"current: {digest}")
    else:
        print("status: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
