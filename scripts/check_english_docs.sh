#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  check_english_docs.sh [skill-root]

Checks curated markdown documents for Korean text.

Exclusions:
  - README.md public-facing repository entry document
  - mold/** research documents
  - mold/temp/** generated traces and scratch artifacts
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

matches="$(rg -n "[가-힣]" . \
  --glob "*.md" \
  --glob "!README.md" \
  --glob "!mold/**" \
  --glob "!mold/temp/**" || true)"

popd >/dev/null

if [[ -n "$matches" ]]; then
  echo "[FAIL] Korean text found in curated markdown documents:" >&2
  printf '%s\n' "$matches" >&2
  exit 1
fi

echo "[OK] Curated markdown documents are English-only (excluding README.md)."
