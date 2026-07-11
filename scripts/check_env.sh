#!/usr/bin/env bash
# Environment contract doctor for developing/validating the codeguide skill.
#
# Supported toolchain (the declared contract):
#   bash   >= 3.2   (macOS system bash is the floor; scripts avoid 4.x-only features)
#   python3 >= 3.9  (scripts/ are stdlib-only at runtime)
#   bats   >= 1.5   (bats-core; the full suite lives in tests/*.bats)
#   git             (path resolution and shadow freshness use git plumbing)
#   pytest          (dev-only, from requirements-dev.txt; tests/test_*.py)
#
# Exit 0 when every requirement is satisfied; exit 1 otherwise, after printing
# one remediation line per missing/outdated tool. No network access, no writes.

set -u

usage() {
  cat <<'EOF'
Usage:
  check_env.sh [--skip-pytest]

Verifies the supported toolchain for developing and validating the codeguide
skill (bash, python3, bats, git, pytest). Prints one [OK]/[FAIL] line per
requirement and a remediation hint for each failure.

Options:
  --skip-pytest   Do not require the pytest dev dependency (bats-only workflows).
  -h, --help      Show this message.
EOF
}

SKIP_PYTEST="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-pytest) SKIP_PYTEST="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[ERROR] Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

FAILURES=0

ok() { printf '[OK] %s\n' "$1"; }
fail() {
  printf '[FAIL] %s\n' "$1"
  printf '       remediation: %s\n' "$2"
  FAILURES=$((FAILURES + 1))
}

# bash: version of the interpreter running this script.
if (( BASH_VERSINFO[0] > 3 || (BASH_VERSINFO[0] == 3 && BASH_VERSINFO[1] >= 2) )); then
  ok "bash ${BASH_VERSION} (>= 3.2)"
else
  fail "bash ${BASH_VERSION} is older than 3.2" "install a newer bash (brew install bash / apt install bash)"
fi

# python3 >= 3.9
if command -v python3 >/dev/null 2>&1; then
  PY_VERSION="$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))' 2>/dev/null || true)"
  if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null; then
    ok "python3 ${PY_VERSION} (>= 3.9)"
  else
    fail "python3 ${PY_VERSION:-unknown} is older than 3.9" "install Python 3.9+ (brew install python / pyenv install 3.12)"
  fi
else
  fail "python3 not found on PATH" "install Python 3.9+ (brew install python / apt install python3)"
fi

# bats >= 1.5
if command -v bats >/dev/null 2>&1; then
  BATS_VERSION_RAW="$(bats --version 2>/dev/null | head -n 1 || true)"
  BATS_VERSION="$(printf '%s' "$BATS_VERSION_RAW" | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1 || true)"
  BATS_MAJOR="${BATS_VERSION%%.*}"
  BATS_MINOR="$(printf '%s' "$BATS_VERSION" | cut -d. -f2)"
  if [[ -n "$BATS_VERSION" ]] && (( BATS_MAJOR > 1 || (BATS_MAJOR == 1 && BATS_MINOR >= 5) )); then
    ok "bats ${BATS_VERSION} (>= 1.5)"
  else
    fail "bats ${BATS_VERSION:-unknown} is older than 1.5" "install bats-core 1.5+ (brew install bats-core / npm i -g bats)"
  fi
else
  fail "bats not found on PATH" "install bats-core 1.5+ (brew install bats-core / npm i -g bats)"
fi

# git: presence is enough (only plumbing commands are used).
if command -v git >/dev/null 2>&1; then
  ok "git $(git --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)"
else
  fail "git not found on PATH" "install git (xcode-select --install / apt install git)"
fi

# pytest: dev dependency, importable by the python3 above.
if [[ "$SKIP_PYTEST" == "true" ]]; then
  ok "pytest check skipped (--skip-pytest)"
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import pytest' 2>/dev/null; then
  ok "pytest $(python3 -c 'import pytest; print(pytest.__version__)' 2>/dev/null)"
else
  fail "pytest is not importable by python3" "python3 -m pip install -r $(dirname "$0")/../requirements-dev.txt"
fi

if (( FAILURES > 0 )); then
  printf '[RESULT] Environment check failed with %d issue(s).\n' "$FAILURES"
  exit 1
fi
printf '[RESULT] Environment check passed.\n'
