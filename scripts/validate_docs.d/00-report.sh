#!/usr/bin/env bash
# validate_docs.d/00-report.sh — Reporting core: issue counter and the pass/fail/soft-warn output contract.
# Sourced by validate_docs.sh after CLI/global setup; not executable alone.
# Split from validate_docs.sh (behavior-preserving; function bodies verbatim).

fail() {
  if [[ "$MODE" == "strict" ]]; then
    echo "[FAIL] $1" >&2
  else
    echo "[WARN] $1" >&2
  fi
  ISSUE_COUNT=$((ISSUE_COUNT + 1))
}

pass() {
  echo "[PASS] $1"
}

# Unlike fail(), always prints [WARN] and never affects ISSUE_COUNT/exit code —
# for signals that are informational in BOTH advisory and strict mode (e.g. the
# resume_state_revision non-numeric check in the session-resume-contract.md).
soft_warn() {
  echo "[WARN] $1" >&2
}
