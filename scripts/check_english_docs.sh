#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  check_english_docs.sh [skill-root]

Checks curated markdown documents for Korean text and required legacy-reference warnings.

Exclusions:
  - README.md public-facing repository entry document
  - mold/** or mold-named research documents
  - temp/**, tmp/**, .serena/**, and mold/temp/** generated traces and scratch artifacts

Special checks:
  - references/claude-sc/*.md legacy playbooks are not language-scanned, but each file must
    include the standard "Legacy comparative reference only" warning.
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

pushd "$SKILL_ROOT" >/dev/null

matches="$(
  python3 - <<'PY'
import pathlib
import re

root = pathlib.Path(".")
korean = re.compile(r"[가-힣]")
fence = re.compile(r"```.*?```", re.DOTALL)
tick = chr(96)
inline_code = re.compile(re.escape(tick) + r"[^" + re.escape(tick) + r"]*" + re.escape(tick))
legacy_markers = (
    "> [!CAUTION]",
    "**LEGACY REFERENCE ONLY**",
    "Legacy comparative reference only",
    "not active Codeguide policy",
    "Active policy is defined in `SKILL.md`",
)

def is_claude_sc(path: pathlib.Path) -> bool:
    parts = path.parts
    return len(parts) >= 2 and parts[0] == "references" and parts[1] == "claude-sc"

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

for path in sorted(root.rglob("*.md")):
    if is_claude_sc(path):
        text = path.read_text(encoding="utf-8")
        header = text[:1200]
        missing = [marker for marker in legacy_markers if marker not in header]
        if missing:
            print(f"{path.as_posix()}:1:missing required legacy warning")
        continue
    if should_skip(path):
        continue
    text = path.read_text(encoding="utf-8")
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

echo "[OK] Curated markdown documents are English-only and legacy references are guarded."
