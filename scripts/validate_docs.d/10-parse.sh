#!/usr/bin/env bash
# validate_docs.d/10-parse.sh — Generic document inspection: field extraction, structural checks, date/epoch helpers, filename parsers, slugs.
# Sourced by validate_docs.sh after CLI/global setup; not executable alone.
# Split from validate_docs.sh (behavior-preserving; function bodies verbatim).

file_mtime_epoch() {
  local file_path="$1"
  if stat -f %m "$file_path" >/dev/null 2>&1; then
    stat -f %m "$file_path"
  else
    stat -c %Y "$file_path"
  fi
}

file_age_days() {
  local file_path="$1"
  local now_epoch
  local mtime_epoch

  now_epoch="$(date +%s)"
  mtime_epoch="$(file_mtime_epoch "$file_path")"
  echo $(((now_epoch - mtime_epoch) / 86400))
}

parse_iso_date_epoch() {
  local value="$1"
  local parsed=""
  local date_part=""

  if [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    if date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$value" "+%s" >/dev/null 2>&1; then
      parsed="$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$value" "+%s")"
    else
      parsed="$(date -u -d "$value" "+%s" 2>/dev/null || true)"
    fi
  fi

  if [[ -z "$parsed" ]]; then
    date_part="$(printf "%s" "$value" | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n 1 || true)"
    if [[ -n "$date_part" ]]; then
      if date -j -f "%Y-%m-%d" "$date_part" "+%s" >/dev/null 2>&1; then
        parsed="$(date -j -f "%Y-%m-%d" "$date_part" "+%s")"
      else
        parsed="$(date -d "$date_part" "+%s" 2>/dev/null || true)"
      fi
    fi
  fi

  if [[ "$parsed" =~ ^[0-9]+$ ]]; then
    printf "%s" "$parsed"
  else
    printf "0"
  fi
}

file_effective_epoch() {
  local file_path="$1"
  local last_updated
  local parsed_epoch

  last_updated="$(extract_field_value "$file_path" "last_updated")"
  if [[ -n "$last_updated" ]]; then
    parsed_epoch="$(parse_iso_date_epoch "$last_updated")"
    if (( parsed_epoch > 0 )); then
      printf "%s" "$parsed_epoch"
      return
    fi
  fi

  file_mtime_epoch "$file_path"
}

file_newest_change_epoch() {
  local file_path="$1"
  local last_updated
  local parsed_epoch=0
  local mtime_epoch

  last_updated="$(extract_field_value "$file_path" "last_updated")"
  if [[ -n "$last_updated" ]]; then
    parsed_epoch="$(parse_iso_date_epoch "$last_updated")"
  fi

  mtime_epoch="$(file_mtime_epoch "$file_path")"
  if (( parsed_epoch > mtime_epoch )); then
    printf "%s" "$parsed_epoch"
  else
    printf "%s" "$mtime_epoch"
  fi
}

check_timestamp_field_valid_non_future() {
  local file_path="$1"
  local key="$2"
  local label="$3"
  local value
  local parsed_epoch
  local now_epoch

  value="$(extract_field_value "$file_path" "$key")"
  if [[ -z "$value" ]]; then
    fail "${key} is present but empty in ${label}: $file_path"
    return 1
  fi

  parsed_epoch="$(parse_iso_date_epoch "$value")"
  if (( parsed_epoch <= 0 )); then
    fail "${key} must be a valid ISO date in ${label}: ${value} (${file_path})"
    return 1
  fi

  now_epoch="$(date +%s)"
  if (( parsed_epoch > now_epoch )); then
    fail "${key} must not be in the future in ${label}: ${value} (${file_path})"
    return 1
  fi

  return 0
}

escape_ere_literal() {
  printf "%s" "$1" | sed -E 's/[][(){}.^$*+?|\\]/\\&/g'
}

# SCRIPT_DIR is owned by validate_docs.sh, the shell that owns the run. When this module
# is sourced on its own -- tests, or any caller that wants only the parsers -- the variable
# is unbound, and under `set -u` the strip below aborted with "SCRIPT_DIR: unbound variable"
# instead of degrading. Fall back to this file's own scripts/ directory.
fence_strip_script_dir() {
  if [[ -n "${SCRIPT_DIR:-}" ]]; then
    printf "%s" "$SCRIPT_DIR"
    return 0
  fi
  (cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
}

# A stripped copy is trusted only when it is a readable, NON-EMPTY file that the source
# document has not outrun. With $2 given the entry is also checked against its source; the
# staged-write caller omits it, because there the question is only "did the writer produce
# complete output", not "is this still current".
#
# Every writer of a stripped copy -- this module and the corpus pre-strip in
# validate_docs.sh -- terminates its output with a newline even when the document has no
# content lines at all, so zero bytes never means "the whole document was fenced". It means
# truncated, interrupted or poisoned. The previous code trusted `-f` alone, and in a real
# run that was the ONLY branch ever taken (the pre-strip covers the corpus, so the strip
# below spawns zero times): a single zero-byte entry therefore made every field on that
# document read as empty, i.e. a capsule with no metadata -- the worst available answer and
# the hardest to attribute.
#
# The freshness half was asked for in r01 and only the zero-length half shipped, so a
# document rewritten after the pre-strip was answered from the pre-run snapshot for the
# rest of the run (r02 finding 7). Its exact strength, stated rather than implied: the
# test is `source is not STRICTLY newer than entry`, and `-nt` on bash 3.2 compares whole
# seconds. A rewrite in the same second as the pre-strip is therefore still missed, and
# equal timestamps must count as fresh -- a scaffold written and validated inside one
# second is the normal case in the test suite, and rejecting it would send every read back
# to a per-call python spawn, which is the 29s -> 100s regression the cache exists to
# prevent.
fence_cache_entry_usable() {
  local entry="$1"
  local src="${2:-}"

  [[ -r "$entry" && -s "$entry" ]] || return 1
  [[ -z "$src" || ! "$src" -nt "$entry" ]]
}

# Write the fence-stripped form of $1 to $2. Same grammar (shadow_doc_parse) and same
# trailing-newline contract as the corpus pre-strip in validate_docs.sh.
fence_strip_into() {
  local src="$1"
  local out="$2"
  local script_dir
  script_dir="$(fence_strip_script_dir)"

  python3 - "$src" "$script_dir" > "$out" 2>/dev/null <<'STRIPPY'
import sys

sys.path.insert(0, sys.argv[2])
sys.dont_write_bytecode = True
import shadow_doc_parse

lines = shadow_doc_parse.read_lines(sys.argv[1])
sys.stdout.write("\n".join(shadow_doc_parse.content_lines(lines)) + "\n")
STRIPPY
}

# Set FENCE_STRIPPED_PATH to a copy of $1 with fenced blocks removed, computed once per file.
#
# It assigns a global rather than printing, and it does NOT create the cache root: every
# caller of extract_field_value uses `$( ... )`, so this function always runs in a SUBSHELL.
# A cache dir or an EXIT trap created here would be created and destroyed inside that
# substitution -- measured: slower than no cache at all, plus a leaked temp dir per read.
# The owning shell creates FENCE_STRIP_CACHE once (validate_docs.sh) and exports it; writes
# into it from a subshell survive because the filesystem is shared even when variables are not.
# Sourced outside the validator (tests), the fallback strips per call: correct, just slower.
fence_stripped_file() {
  local src="$1"
  FENCE_STRIPPED_PATH="$src"
  [[ -f "$src" ]] || return 0

  local dest=""
  local staged=""
  if [[ -n "${FENCE_STRIP_CACHE:-}" && -d "$FENCE_STRIP_CACHE" ]]; then
    dest="$FENCE_STRIP_CACHE/${src#/}"
    if fence_cache_entry_usable "$dest" "$src"; then
      FENCE_STRIPPED_PATH="$dest"
      return 0
    fi
    mkdir -p "$(dirname "$dest")" 2>/dev/null || dest=""
  fi
  if [[ -z "$dest" ]]; then
    dest="$(mktemp)" || return 0
  fi

  # Stage then rename, so no reader can ever be handed a half-written entry, and keep the
  # ORIGINAL path on ANY failure. Falling back to an empty stripped file would blank every
  # field the caller asks for, which reads as a document with no metadata at all -- a far
  # worse failure than the fence-blindness this replaces. An unusable entry that was already
  # in the cache is removed here rather than served, so the next read retries it.
  staged="${dest}.strip.$$"
  if fence_strip_into "$src" "$staged" \
    && fence_cache_entry_usable "$staged" \
    && mv -f "$staged" "$dest" 2>/dev/null; then
    FENCE_STRIPPED_PATH="$dest"
  else
    rm -f "$staged" "$dest"
  fi
}

# Key-presence probe answered by the SAME grammar as extract_field_value: same
# fence-stripped copy, same `^- key:` column-0 anchor, same case sensitivity. It takes a
# KEY and never a caller-supplied regex, which is deliberate -- see below.
#
# These two must never diverge. Before the task they agreed by
# accident, because both were fence-blind. Making only the VALUE reader fence-aware
# reintroduced the exact defect this line of work exists to end: on a task whose only
# `- status: in_progress` sits in a quoted template the validator emitted "in-progress task
# is stale" from a fence-blind probe while every other rule in the same run read the file as
# `planned` -- one document, two rules, opposite answers.
#
# The r01 fix for that shipped a general `field_pattern_present "$file" "$regex"` helper,
# and r02 found the SAME class one axis over: `^- status:.*in_progress` asks an ANY-LINE
# question while extract_field_value answers a FIRST-LINE one, so a capsule with
# `- status: planned` above a later `- status: in_progress` failed the freshness gate in a
# run that read it as planned. A helper that accepts an arbitrary pattern cannot hold the
# invariant, because the pattern is where the divergence lives. Presence questions about a
# VALUE are answered by comparing the value extract_field_value already returned.
#
# The anchor is duplicated by hand rather than shared through a variable because a shared
# ERE fragment reads as configurable; it is not. If you change one of these two anchors,
# change the other in the same edit. Both directions are pinned: widening the PROBE fails
# "validate_docs answers key presence with the same column-0 anchor the value read uses",
# and widening the VALUE reader fails "validate_docs answers a field VALUE with the same
# column-0 anchor the presence probe uses". Only the first existed before, so widening the
# value reader alone left all 627 tests green while this comment claimed otherwise (r03
# mutant M21) -- the anchor test asserts an indented-only field reports "missing", which
# the still-narrow probe delivers on its own.
#
# What the anchor difference IS, stated once: the shared reader matches
# `^\s*-\s*key\s*:`, so it also tolerates leading indentation, several spaces after the
# dash and a space before the colon. This reader tolerates none of those. That is a
# grammar difference rather than a fence difference; widening it is owed its own
# before/after evidence and stays deliberately unbuilt.
field_key_present() {
  local file_path="$1"
  local key="$2"

  fence_stripped_file "$file_path"
  grep -qE "^- ${key}:" "$FENCE_STRIPPED_PATH" 2>/dev/null
}

# The task-index ROW grammar -- a different question from `- key:`, so it gets its own
# name rather than a regex argument to the field probe.
#
# Three readers asked it, each with its own spelling: two `grep -qE "^- <ref> "` probes in
# validate_docs.sh and the `while read` walk in 30-rules-task.sh. All three were fence-blind,
# which the PLAN's residual list defended as "they agree, so move them together or not at
# all". They agreed on a FALSEHOOD: a task whose only index row sits inside a quoted
# ``` block was silently accepted by the probes AND assigned a section by the walk, so the
# validator reported "row is listed under Done" about a row no markdown reader would find
# They also did not agree: the probes
# required a space after the ref while the walk did not, so a bare `- TASK-foo` row produced
# "task-index missing row" from one reader and a section verdict from the other. Moving them
# together means one fence rule and one row shape, here.
#
# The trailing group matches the walk's `^- (TASK-[A-Za-z0-9._-]+)` boundary exactly: a
# ref ends at whitespace or end of line, so `- TASK-foo-2 planned` is not a row for TASK-foo.
# That sentence used to have nothing behind it: r03 deleted the group and all 627 tests
# stayed green (mutant M2). It is now pinned by "validate_docs does not read a longer
# task-index ref as the row for a shorter one".
#
# $2 is a LITERAL ref and is escaped HERE. Both row helpers take a literal and escape
# internally; the previous split -- this one interpolating raw while its sibling below took
# pre-escaped input from its caller -- is the escaping AXIS, and two helpers with opposite
# argument contracts is the same trap one level up. The walk's charset `[A-Za-z0-9._-]`
# permits a dot and no rule forbids a dotted task filename, so unescaped a probe for
# `TASK-foo.bar-01` matched the row `- TASK-fooxbar-01`: "task-index missing row" silenced
# while the walk captured a different ref.
task_index_row_present() {
  local index_file="$1"
  local task_ref_escaped
  task_ref_escaped="$(escape_ere_literal "$2")"

  fence_stripped_file "$index_file"
  grep -qE "^- ${task_ref_escaped}"'([[:space:]]|$)' "$FENCE_STRIPPED_PATH" 2>/dev/null
}

# The decision-index ROW grammar, in both the section form and the legacy table form.
# $2 is a LITERAL base name, escaped HERE -- see the note on the sibling above. A decision
# file name carries dots, so this one was never safe raw; the caller used to escape it,
# which is why only the task-index probe was ever wrong.
#
# Its own named helper for the same reason as the two above: the alternative would be a
# generic "does this regex match outside fences" helper, and a caller-supplied pattern is
# where these divergences live. Unlike the task-index rows there is only ONE reader of
# decision-index.md, so this could not CONTRADICT anything -- but a row that exists only
# inside a quoted example still silenced "decision index missing row" entirely, which is
# the same "a template answers for the real thing" hole as the bucket-index unit rows.
# Found by the task's own axis enumeration, not by a review.
decision_index_row_present() {
  local index_file="$1"
  local decision_base_escaped
  decision_base_escaped="$(escape_ere_literal "$2")"

  fence_stripped_file "$index_file"
  grep -qE "(^- ${decision_base_escaped} \||^\| ${decision_base_escaped} \|)" \
    "$FENCE_STRIPPED_PATH" 2>/dev/null
}

# The issue-tracker README ROW grammar -- a markdown TABLE cell rather than a `- ` bullet,
# so it gets its own name for the same reason the two above do.
#
# It lived inline in check_issue_tracker_integrity at two call sites and carried BOTH open
# axes at once: the id was interpolated raw (so `ISSUE-2026.01.01-x` matched the row
# `ISSUE-2026x01x01-x`) and the grep read the RAW README (so a row that exists only inside
# a quoted "Row format" example silenced "missing index row" entirely, reproduced with its
# control). The escaping half was closed in place last round and the fence half was not --
# on the two lines that round edited. Making it a helper with the SAME contract as its two
# siblings, a literal escaped internally against the fence-stripped copy, is what stops the
# next site from picking one of the two.
issue_index_row_present() {
  local index_file="$1"
  local issue_id_escaped
  issue_id_escaped="$(escape_ere_literal "$2")"

  fence_stripped_file "$index_file"
  grep -qE "\|[[:space:]]*${issue_id_escaped}(\.md)?[[:space:]]*\|" \
    "$FENCE_STRIPPED_PATH" 2>/dev/null
}

# Extract the value part of a "- key: value" line. Returns empty if key missing or value empty.
extract_field_value() {
  local file_path="$1"
  local key="$2"
  local raw
  # Fence-aware: a fenced EXAMPLE must never outrank the real field. The fence rule
  # is shadow_doc_parse, the same one every other reader uses -- a shell-native fence
  # filter here would be a second implementation of the thing this line of work exists
  # to end.
  #
  # Stripping is cached per FILE, not per field read: a python spawn per read measured
  # 4x the old grep, and a capsule is read 9-25 times. The `^- key:` column-0 anchoring
  # and the grep that uses it are unchanged.
  #
  # This comment used to end "so this adds fence awareness and nothing else", which was
  # FALSE when it was written and is true now. Delegating the strip also changed what a
  # LINE is: the strip consumed `str.splitlines()`, which breaks on VT, FF, FS, GS, RS,
  # NEL, U+2028 and U+2029, while the grep below and every other raw reader break on `\n`
  # alone -- so on a document containing no fence at all this reader could return a value
  # HEAD's grep did not. The line rule is
  # now shared too, in shadow_doc_parse.split_lines, and it is `\n`-only because that is
  # what CommonMark, grep, awk, sed and wc -l all mean by a line. Pinned by the three
  # form-feed cases in validate_docs.bats, not by this sentence.
  fence_stripped_file "$file_path"
  raw="$(grep -E "^- ${key}:" "$FENCE_STRIPPED_PATH" 2>/dev/null | head -n 1 | sed "s/^- ${key}:[[:space:]]*//" || true)"
  # Trim whitespace. Every enum, equality and reference rule in the validator is a literal
  # string compare against this value, so an untrimmed one fails them all; r03 deleted this
  # line and all 627 tests stayed green (mutant M23), which is now caught by
  # "validate_docs trims trailing whitespace off a field value before any rule compares it".
  printf "%s" "$raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# Check that a field exists AND has a non-empty value
check_field_non_empty() {
  local file_path="$1"
  local key="$2"
  local label="$3"
  local value

  if ! field_key_present "$file_path" "$key"; then
    fail "${key} is missing in ${label}: $file_path"
    return 1
  fi

  value="$(extract_field_value "$file_path" "$key")"
  if [[ -z "$value" ]]; then
    fail "${key} is present but empty in ${label}: $file_path"
    return 1
  fi
  return 0
}

check_any_field_non_empty() {
  local file_path="$1"
  local label="$2"
  shift 2
  local key
  local value
  local keys_text

  for key in "$@"; do
    value="$(extract_field_value "$file_path" "$key")"
    if [[ -n "$value" ]]; then
      return 0
    fi
  done

  keys_text="$(printf "%s|" "$@")"
  keys_text="${keys_text%|}"
  fail "one of ${keys_text} is required and non-empty in ${label}: $file_path"
  return 1
}

# Check field exists (key presence only, for backward compat in advisory mode)
check_field_exists() {
  local file_path="$1"
  local key="$2"
  local label="$3"

  if ! field_key_present "$file_path" "$key"; then
    fail "${key} is missing in ${label}: $file_path"
    return 1
  fi
  return 0
}

check_field_value_equals() {
  local file_path="$1"
  local key="$2"
  local expected="$3"
  local label="$4"
  local value

  value="$(extract_field_value "$file_path" "$key")"
  if [[ -z "$value" ]]; then
    fail "${key} is missing in ${label}: $file_path"
    return 1
  fi

  if [[ "$value" != "$expected" ]]; then
    fail "invalid ${key} in ${label}: expected ${expected}, found ${value} (${file_path})"
    return 1
  fi
  return 0
}

# Freshness check using last_updated field first, then mtime fallback
check_freshness_days() {
  local file_path="$1"
  local max_days="$2"
  local label="$3"
  local age_days
  local last_updated

  if (( max_days == 0 )); then
    pass "${label} age-based freshness check disabled: $file_path"
    return 0
  fi

  last_updated="$(extract_field_value "$file_path" "last_updated")"
  if [[ -n "$last_updated" ]]; then
    # Parse ISO date from last_updated (supports YYYY-MM-DDTHH:MM:SSZ and YYYY-MM-DD)
    local lu_date
    lu_date="$(printf "%s" "$last_updated" | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n 1 || true)"
    if [[ -n "$lu_date" ]]; then
      local lu_epoch now_epoch
      lu_epoch="$(parse_iso_date_epoch "$last_updated")"
      now_epoch="$(date +%s)"
      if (( lu_epoch > 0 )); then
        age_days=$(( (now_epoch - lu_epoch) / 86400 ))
        if (( age_days > max_days )); then
          fail "${label} is stale by last_updated (${age_days} days > ${max_days}): $file_path"
        else
          pass "${label} freshness OK by last_updated (${age_days} days): $file_path"
        fi
        return
      fi
    fi
  fi

  # Fallback to file mtime
  age_days="$(file_age_days "$file_path")"
  if (( age_days > max_days )); then
    fail "${label} is stale by mtime (${age_days} days > ${max_days}): $file_path"
  else
    pass "${label} freshness OK by mtime (${age_days} days): $file_path"
  fi
}

check_file_exists() {
  local file_path="$1"
  local label="$2"
  if [[ -f "$file_path" ]]; then
    pass "$label exists"
  else
    fail "$label is missing: $file_path"
  fi
}

check_dir_exists() {
  local dir_path="$1"
  local label="$2"
  if [[ -d "$dir_path" ]]; then
    pass "$label exists"
  else
    fail "$label is missing: $dir_path"
  fi
}

check_line_limit() {
  local file_path="$1"
  local max_lines="$2"
  local label="$3"
  local lines

  lines="$(wc -l < "$file_path" | tr -d ' ')"
  if (( lines > max_lines )); then
    fail "$label is too large (${lines} lines > ${max_lines}): $file_path"
  else
    pass "$label size OK (${lines}/${max_lines}): $file_path"
  fi
}

check_enum_membership() {
  local value="$1"
  local field_name="$2"
  local label="$3"
  shift 3
  local allowed_values=("$@")
  local candidate
  local allowed_text

  if [[ -z "$value" ]]; then
    return 0
  fi

  for candidate in "${allowed_values[@]}"; do
    if [[ "$value" == "$candidate" ]]; then
      return 0
    fi
  done

  allowed_text="$(printf "%s|" "${allowed_values[@]}")"
  allowed_text="${allowed_text%|}"
  fail "invalid ${field_name} value in ${label}: ${value} (allowed: ${allowed_text})"
  return 1
}

REPORT_FILE_TASK_ID=""
REPORT_FILE_PLAN_VERSION=""
REPORT_FILE_EVALUATOR=""
REPORT_FILE_ROUND=""
REPORT_FILE_PLAN_REF=""

parse_evaluator_report_filename() {
  local report_base="$1"

  REPORT_FILE_TASK_ID=""
  REPORT_FILE_PLAN_VERSION=""
  REPORT_FILE_EVALUATOR=""
  REPORT_FILE_ROUND=""
  REPORT_FILE_PLAN_REF=""

  if [[ "$report_base" =~ ^PLAN-([A-Za-z0-9._-]+)-(v[0-9]+\.[0-9]+)-review-([A-Za-z0-9._]+)(-[A-Za-z0-9._-]+)?-(r[0-9]{2})\.md$ ]]; then
    REPORT_FILE_TASK_ID="${BASH_REMATCH[1]}"
    REPORT_FILE_PLAN_VERSION="${BASH_REMATCH[2]}"
    REPORT_FILE_EVALUATOR="${BASH_REMATCH[3]}"
    REPORT_FILE_ROUND="${BASH_REMATCH[5]}"
    REPORT_FILE_PLAN_REF="PLAN-${REPORT_FILE_TASK_ID}-${REPORT_FILE_PLAN_VERSION}"
    return 0
  fi

  return 1
}

is_allowed_evaluator_slug() {
  local value="$1"
  case "$value" in
    antigravity|agy|claude|codex|gemini|human)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_placeholder_approval_value() {
  local value="$1"
  local normalized
  normalized="$(printf "%s" "$value" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$normalized" in
    ""|not_required|pending_user_approval|awaiting_approval|none|null|n/a|na|tbd|todo)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# DELIBERATELY FENCE-BLIND, and the only place in the tree where that is load-bearing.
#
# It takes a caller-supplied ERE and greps the RAW file, which is the exact shape this line
# of work deleted `field_pattern_present` for -- so the difference needs writing down
# rather than leaving for the next sweep to "finish". Its 18 invocations all come from
# `check_shadow_policy_files`, and the payload they probe is 100% FENCED on purpose: the
# policy registries carry their declarations inside fenced blocks, and the awk collectors
# that consume those declarations read them raw and agree. Measured on this corpus
# in docs/policy/shadow-regex-patterns.md
# the keys allowed_paths, excluded_paths, validates, cannot_validate and max_promotion_risk
# each appear 8 times and ZERO times outside a fence; shadow-rule-registry.md has `rules:`
# once and zero outside; shadow-validator-catalog.md has `validates:` 18 times and zero
# outside. Making this helper fence-aware turns roughly eighteen strict PASS lines into
# FAILs on the live corpus.
#
# So the boundary is: the `- key:` CAPSULE grammar is fence-aware everywhere; the policy
# REGISTRY grammar is fence-blind everywhere, by the recorded decision, which
# already puts the registry payload outside the shared reader. Do not unify this one.
check_file_contains_pattern() {
  local file_path="$1"
  local pattern="$2"
  local pass_msg="$3"
  local fail_msg="$4"

  if grep -qE -- "$pattern" "$file_path" 2>/dev/null; then
    pass "$pass_msg"
  else
    fail "$fail_msg"
  fi
}

trim_value() {
  printf "%s" "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

is_registry_colon_route() {
  local route="$1"
  python3 - "$SCRIPT_DIR" "$route" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

script_dir = Path(sys.argv[1])
route = sys.argv[2]
sys.path.insert(0, str(script_dir))
from ai_model_registry import RegistryError, load_registry

try:
    registry = load_registry(script_dir.parent / "config" / "ai_model_registry.json")
except RegistryError:
    raise SystemExit(1)

if route not in registry["models"] or ":" not in route:
    raise SystemExit(1)
PY
}

route_slug_for_filename() {
  printf "%s" "$1" | sed 's/[^A-Za-z0-9._-]/-/g'
}

resolve_docs_ref_path() {
  local ref="$1"
  ref="${ref%/}"
  case "$ref" in
    /*) printf "%s" "$ref" ;;
    docs/*) printf "%s/%s" "$PROJECT_ROOT_ABS" "$ref" ;;
    *) printf "%s/%s" "$DOCS_DIR" "$ref" ;;
  esac
}
