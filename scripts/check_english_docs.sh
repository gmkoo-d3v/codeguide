#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  check_english_docs.sh [skill-root]

Checks curated markdown documents for Korean text and structural index constraints.

Exclusions:
  - README.md public-facing repository entry document
  - mold/** or mold-named research documents
  - temp/**, tmp/**, .serena/**, and mold/temp/** generated traces and scratch artifacts

Special checks:
  - SKILL.md, references/index.md, and every _index.md must not contain fenced code blocks.
  - Index bullets with a summary separator must include a backtick-wrapped .md pointer.
    In structural index files, any list bullet with a colon is treated as an index entry;
    write prose notes as paragraphs or avoid colon-entry shape when no pointer is intended.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if (( $# > 1 )); then
  echo "[ERROR] Too many arguments" >&2
  usage
  exit 1
fi

SKILL_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if [[ ! -d "$SKILL_ROOT" ]]; then
  echo "[ERROR] Skill root does not exist: $SKILL_ROOT" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[ERROR] python3 is required for documentation validation but was not found in PATH" >&2
  exit 1
fi

pushd "$SKILL_ROOT" >/dev/null

matches="$(
  python3 - <<'PY'
import pathlib
import re

root = pathlib.Path(".")
korean = re.compile(r"[가-힣]")
tick = chr(96)
triple_tick = re.escape(tick) * 3
fence = re.compile(triple_tick + r".*?" + triple_tick, re.DOTALL)
fence_marker = re.compile(r"^\s*" + triple_tick)
inline_code = re.compile(re.escape(tick) + r"[^" + re.escape(tick) + r"]*" + re.escape(tick))
md_pointer = re.compile(re.escape(tick) + r"[^" + re.escape(tick) + r"]+\.md" + re.escape(tick))
index_bullet = re.compile(r"^\s*[-*+]\s+")
def should_skip(path: pathlib.Path) -> bool:
    parts = path.parts
    name = path.name
    if name == "README.md":
        return True
    if "mold" in parts or "mold" in name:
        return True
    if "temp" in parts or "tmp" in parts or ".serena" in parts:
        return True
    return False

def is_structural_index_target(path: pathlib.Path) -> bool:
    return path.name == "_index.md" or path.name == "SKILL.md" or path.as_posix() == "references/index.md"

def needs_index_entry_check(path: pathlib.Path) -> bool:
    return path.name == "_index.md" or path.as_posix() == "references/index.md"

for path in sorted(root.rglob("*.md")):
    if should_skip(path):
        continue
    text = path.read_text(encoding="utf-8")
    if is_structural_index_target(path):
        for lineno, line in enumerate(text.splitlines(), start=1):
            if fence_marker.search(line):
                print(f"{path.as_posix()}:{lineno}:fenced code block is not allowed in structural index files")
            # Convention: colon-bearing list bullets in structural indexes are entries and must point to .md.
            if needs_index_entry_check(path) and index_bullet.search(line) and ":" in line and not md_pointer.search(line):
                print(f"{path.as_posix()}:{lineno}:index entry must include a backtick-wrapped .md pointer")
    text = fence.sub("", text)
    text = inline_code.sub("", text)
    for lineno, line in enumerate(text.splitlines(), start=1):
        if korean.search(line):
            print(f"{path.as_posix()}:{lineno}:{line}")
PY
)"

popd >/dev/null

if [[ -n "$matches" ]]; then
  echo "[FAIL] Curated markdown validation failed:" >&2
  printf '%s\n' "$matches" >&2
  exit 1
fi

echo "[OK] Curated markdown documents are English-only and structural indexes are valid."
