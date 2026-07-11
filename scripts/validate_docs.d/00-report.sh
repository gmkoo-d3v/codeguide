#!/usr/bin/env bash
# validate_docs.d/00-report.sh — Reporting core: issue counter and the pass/fail/soft-warn output contract.
# Sourced by validate_docs.sh after CLI/global setup; not executable alone.
# Split from validate_docs.sh (behavior-preserving; function bodies verbatim).
#
# Rule-id / JSON-record contract (see validate_docs.sh header + README):
#   Every issue carries a stable id = the name of the function that called
#   fail()/soft_warn() (bash FUNCNAME[1]) plus a caller = that function's own
#   caller (FUNCNAME[2]); either defaults to "main" for the top-level phase
#   flow. Consumers discriminate rules by (id, caller, message-prefix):
#   helper-emitted issues carry the helper as id and the invoking rule (or
#   "main") as caller. In text mode (default / --format text) nothing below
#   changes: output stays byte-identical. Under VALIDATE_FORMAT=json the human
#   [FAIL]/[WARN]/[PASS] echoes are suppressed and each issue is appended to
#   $VALIDATE_JSON_RECORD_FILE as a NUL-delimited quadruple (tier, id, caller,
#   message). A bash string can never hold a NUL byte, so no message content —
#   however hostile (quotes, backslashes, tabs, newlines, non-ASCII) — can
#   forge a field or record boundary. emit_json_result() serializes the file
#   once via a single python3 invocation at result time.

fail() {
  if [[ "${VALIDATE_FORMAT:-text}" == "json" ]]; then
    local __tier="warn"
    [[ "$MODE" == "strict" ]] && __tier="fail"
    printf '%s\0%s\0%s\0%s\0' "$__tier" "${FUNCNAME[1]:-main}" "${FUNCNAME[2]:-main}" "$1" >> "$VALIDATE_JSON_RECORD_FILE"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
    return
  fi
  if [[ "$MODE" == "strict" ]]; then
    echo "[FAIL] $1" >&2
  else
    echo "[WARN] $1" >&2
  fi
  ISSUE_COUNT=$((ISSUE_COUNT + 1))
}

pass() {
  if [[ "${VALIDATE_FORMAT:-text}" == "json" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    return
  fi
  echo "[PASS] $1"
}

# Unlike fail(), always prints [WARN] and never affects ISSUE_COUNT/exit code —
# for signals that are informational in BOTH advisory and strict mode (e.g. the
# resume_state_revision non-numeric check in the session-resume-contract.md).
soft_warn() {
  if [[ "${VALIDATE_FORMAT:-text}" == "json" ]]; then
    printf '%s\0%s\0%s\0%s\0' "warn" "${FUNCNAME[1]:-main}" "${FUNCNAME[2]:-main}" "$1" >> "$VALIDATE_JSON_RECORD_FILE"
    return
  fi
  echo "[WARN] $1" >&2
}

# Serialize the captured issue records into a single JSON object on stdout.
# Called once by validate_docs.sh at result time when --format json is active.
# Reads $VALIDATE_JSON_RECORD_FILE (NUL-delimited tier/id/caller/message
# quadruples), $PASS_COUNT, and the mode/root globals; the "result" field
# mirrors the text-mode exit code (strict + issues => fail, otherwise pass).
# python3 is a hard dependency (preflight-checked), so one invocation is safe.
emit_json_result() {
  local __result="pass"
  if (( ISSUE_COUNT > 0 )) && [[ "$MODE" == "strict" ]]; then
    __result="fail"
  fi
  VALIDATE_JSON_RECORD_FILE="${VALIDATE_JSON_RECORD_FILE:-}" \
  VALIDATE_JSON_MODE="$MODE" \
  VALIDATE_JSON_PROJECT_ROOT="${PROJECT_ROOT_ABS:-$PROJECT_ROOT}" \
  VALIDATE_JSON_PASS_COUNT="${PASS_COUNT:-0}" \
  VALIDATE_JSON_RESULT="$__result" \
  python3 - <<'PY'
import json
import os
import sys

record_path = os.environ.get("VALIDATE_JSON_RECORD_FILE", "")
data = b""
if record_path:
    with open(record_path, "rb") as handle:
        data = handle.read()

fields = data.split(b"\x00")
# fail()/soft_warn() write a trailing NUL after every record, so a non-empty
# file always leaves one empty tail chunk; drop only that trailing sentinel.
if fields and fields[-1] == b"":
    fields.pop()


def decode(raw):
    # surrogateescape keeps even non-UTF-8 bytes round-trippable; json.dumps
    # (ensure_ascii default) then emits pure-ASCII \uXXXX escapes, so stdout is
    # safe under any locale.
    return raw.decode("utf-8", "surrogateescape")


issues = []
fail_count = 0
warn_count = 0
for start in range(0, len(fields), 4):
    tier = decode(fields[start])
    rule_id = decode(fields[start + 1])
    caller = decode(fields[start + 2])
    message = decode(fields[start + 3])
    issues.append({"tier": tier, "id": rule_id, "caller": caller, "message": message})
    if tier == "fail":
        fail_count += 1
    elif tier == "warn":
        warn_count += 1

obj = {
    "mode": os.environ.get("VALIDATE_JSON_MODE", ""),
    "project_root": os.environ.get("VALIDATE_JSON_PROJECT_ROOT", ""),
    "format_version": 1,
    "issues": issues,
    "counts": {
        "fail": fail_count,
        "warn": warn_count,
        "pass": int(os.environ.get("VALIDATE_JSON_PASS_COUNT", "0") or "0"),
    },
    "result": os.environ.get("VALIDATE_JSON_RESULT", "pass"),
}
sys.stdout.write(json.dumps(obj))
sys.stdout.write("\n")
PY
}
