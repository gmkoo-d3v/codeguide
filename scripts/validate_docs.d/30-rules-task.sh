#!/usr/bin/env bash
# validate_docs.d/30-rules-task.sh — Task-ledger rules: status lifecycle, resume capsule, task-index and issue-tracker integrity.
# Sourced by validate_docs.sh after CLI/global setup; not executable alone.
# Split from validate_docs.sh (behavior-preserving; function bodies verbatim).

is_active_task_status() {
  local status="$1"
  case "$status" in
    in_progress|blocked|done) return 0 ;;
    *) return 1 ;;
  esac
}

# Terminal ledger statuses: the task will not be worked further. "done" closed
# successfully; "superseded"/"cancelled" closed without completing (a successor
# task or the disposition field explains why). Terminal-task plan/orchestration
# artifacts are immutable evidence: identity checks still apply, but authorship
# completeness (scope/objective/last_updated) and size caps do not, so schema
# rules added later are not applied retroactively to closed work.
is_terminal_task_status() {
  local status="$1"
  case "$status" in
    done|superseded|cancelled) return 0 ;;
    *) return 1 ;;
  esac
}

# Resume capsule enforcement (references/session-resume-contract.md). Scoped to
# in_progress tasks, since that is the only status the contract requires a
# capsule for. Three independent tiers:
#   - advisory only: no resume_* field at all on the task -> adoption nudge.
#   - strict only: resume_next_action or resume_last_verified PRESENT but
#     empty -> failure (a declared capsule must be truthful). Absent fields
#     never fail strict, so pre-contract task corpora stay safe.
#   - both modes: resume_state_revision present but non-numeric -> a
#     non-blocking warning even under strict (soft_warn, not fail).
RESUME_CAPSULE_FIELDS=(resume_source_head resume_changed_files resume_checkpointed_at resume_state_revision resume_next_action resume_last_verified resume_blockers)

check_resume_capsule_for_task() {
  local task_file="$1"
  local task_ref="$2"
  local field
  local has_any_resume_field="false"
  local field_value
  local revision_value

  # Presence is asked with field_key_present, the same fence-aware grammar the value
  # reads below use. A fence-blind probe here reported a capsule as DECLARED on the
  # strength of a quoted template and then failed it as "present but empty", while
  # suppressing the one truthful finding, "resume capsule missing".
  for field in "${RESUME_CAPSULE_FIELDS[@]}"; do
    if field_key_present "$task_file" "$field"; then
      has_any_resume_field="true"
      break
    fi
  done

  if [[ "$MODE" != "strict" && "$has_any_resume_field" == "false" ]]; then
    fail "resume capsule missing for in_progress task ${task_ref}: adopt it with doc_garden.sh --task-id ${task_ref#TASK-} --resume-checkpoint (see references/session-resume-contract.md)"
  fi

  if [[ "$MODE" == "strict" ]]; then
    for field in resume_next_action resume_last_verified; do
      if field_key_present "$task_file" "$field"; then
        field_value="$(extract_field_value "$task_file" "$field")"
        if [[ -z "$field_value" ]]; then
          fail "${field} is present but empty for in_progress task ${task_ref}: a declared resume capsule must be truthful (references/session-resume-contract.md)"
        fi
      fi
    done
  fi

  if field_key_present "$task_file" "resume_state_revision"; then
    revision_value="$(extract_field_value "$task_file" "resume_state_revision")"
    if [[ ! "$revision_value" =~ ^[0-9]+$ ]]; then
      soft_warn "resume_state_revision is present but non-numeric for in_progress task ${task_ref}: '${revision_value}' ($task_file)"
    fi
  fi
}

# Maps a task-index.md "## <Section>" header to the task.status enum value
# shown under it (mirrors status_to_section in doc_garden.sh, inverted).
task_index_section_status() {
  case "$1" in
    "## Planned")     printf "planned" ;;
    "## In Progress") printf "in_progress" ;;
    "## Blocked")     printf "blocked" ;;
    "## Done")        printf "done" ;;
    "## Superseded")  printf "superseded" ;;
    "## Cancelled")   printf "cancelled" ;;
    *)                printf "" ;;
  esac
}

# Reverse-direction task-index check (the per-task loop already checks that
# every TASK-*.md has a row; this checks every row back against reality):
# every row must reference an existing task file, sit under the section
# matching that file's actual status, and appear only once in the index.
# This is the enforcement mechanism for keeping task-index.md trustworthy
# without physically archiving/moving TASK-*.md files.
check_task_index_integrity() {
  local index_file="$1"
  local all_refs_file
  local section=""
  local expected_status
  local task_ref
  local task_file
  local file_status
  local file_status_primary
  local dup_ref

  all_refs_file="$(mktemp "${TMPDIR:-/tmp}/validate_docs_task_index_refs.XXXXXX")"

  # Walk the fence-stripped copy, the same bytes task_index_row_present probes. While this
  # walk was fence-blind it agreed with the two probes on a falsehood: a row inside a quoted
  # ``` block silenced "task-index missing row" and then earned a section verdict of its
  # own, so the validator reported "row is listed under Done" about a row no markdown reader
  # would find. A `## ` heading inside a fence is
  # gone for the same reason, so a quoted index example can no longer reassign the section
  # of the real rows below it.
  fence_stripped_file "$index_file"

  while IFS= read -r line; do
    if [[ "$line" =~ ^\#\#\  ]]; then
      section="$line"
      continue
    fi
    if [[ "$line" =~ ^-\ (TASK-[A-Za-z0-9._-]+) ]]; then
      task_ref="${BASH_REMATCH[1]}"
      printf "%s\n" "$task_ref" >> "$all_refs_file"
      task_file="$TASK_DIR/${task_ref}.md"

      if [[ ! -f "$task_file" ]]; then
        fail "task-index row for ${task_ref} has no matching task file: expected ${task_file}"
        continue
      fi

      expected_status="$(task_index_section_status "$section")"
      if [[ -n "$expected_status" ]]; then
        file_status="$(extract_field_value "$task_file" "status")"
        # Compare only the first token: some task files append a trailing
        # parenthetical note after the enum value (e.g. "done (Phase 1 r02...)").
        file_status_primary="${file_status%% *}"
        if [[ -n "$file_status_primary" && "$file_status_primary" != "$expected_status" ]]; then
          fail "task-index section mismatch for ${task_ref}: task file status is ${file_status} but row is listed under ${section#"## "}"
        fi
      fi
    fi
  done < "$FENCE_STRIPPED_PATH"

  if [[ -s "$all_refs_file" ]]; then
    while IFS= read -r dup_ref; do
      [[ -n "$dup_ref" ]] && fail "task-index has duplicate rows for ${dup_ref}"
    done < <(sort "$all_refs_file" | uniq -d)
  fi

  rm -f "$all_refs_file"
}

# Runtime issue tracker (docs/issues/current <-> docs/issues/resolved) consistency.
# This tracker is the one docs series that DOES physically move files as part of
# its normal lifecycle (unlike task/plan/orchestration, which stay flat and rely
# on check_task_index_integrity instead), because closing an issue creates a new
# RESOLUTION doc at the same moment, making the move a natural lifecycle event.
check_issue_tracker_integrity() {
  local issue_file
  local issue_base
  local issue_id
  # The two index probes are `issue_index_row_present` (10-parse.sh), beside the task-index
  # and decision-index row helpers and with the same contract: it takes a LITERAL id, does
  # its own ERE escaping, and reads the fence-stripped copy. Both halves were live defects
  # here -- `ISSUE-2026.01.01-x` matched the row `ISSUE-2026x01x01-x` (escaping axis, closed
  # last round at this call site), and a row that existed only inside a quoted example
  # silenced "missing index row" entirely (fence axis, the task r01
  # finding 4). Escaping at the call site and greping the raw file was how one got closed
  # and the other did not; the helper is what keeps them together.
  local issue_status
  local resolved_at
  local resolution_doc_field
  local expected_resolution_base
  local resolution_file
  local resolution_base
  local expected_issue_base
  local all_ids_file
  local dup_id

  all_ids_file="$(mktemp "${TMPDIR:-/tmp}/validate_docs_issue_ids.XXXXXX")"

  if [[ -d "$ISSUE_TRACKER_CURRENT_DIR" ]]; then
    while IFS= read -r issue_file; do
      issue_base="$(basename "$issue_file")"
      issue_id="${issue_base%.md}"
      printf "%s\n" "$issue_base" >> "$all_ids_file"
      issue_status="$(extract_field_value "$issue_file" "status")"

      check_enum_membership "$issue_status" "issue.status" "$issue_file" open investigating blocked fixed_pending_verify reopened || true
      if [[ "$issue_status" == "resolved" ]]; then
        fail "issue ${issue_base} is status: resolved but still lives in docs/issues/current/ (move it to docs/issues/resolved/ with a paired RESOLUTION doc)"
      fi

      if [[ -f "$ISSUE_TRACKER_CURRENT_DIR/README.md" ]] && ! issue_index_row_present "$ISSUE_TRACKER_CURRENT_DIR/README.md" "$issue_id"; then
        fail "docs/issues/current/README.md missing index row for ${issue_base}"
      fi
    done < <(find "$ISSUE_TRACKER_CURRENT_DIR" -maxdepth 1 -type f -name 'ISSUE-*.md' | sort)
  fi

  if [[ -d "$ISSUE_TRACKER_RESOLVED_DIR" ]]; then
    while IFS= read -r issue_file; do
      issue_base="$(basename "$issue_file")"
      issue_id="${issue_base%.md}"
      printf "%s\n" "$issue_base" >> "$all_ids_file"
      issue_status="$(extract_field_value "$issue_file" "status")"
      resolved_at="$(extract_field_value "$issue_file" "resolved_at")"
      resolution_doc_field="$(extract_field_value "$issue_file" "resolution_doc")"

      if [[ "$issue_status" != "resolved" ]]; then
        fail "issue ${issue_base} lives in docs/issues/resolved/ but status is '${issue_status}' (expected resolved)"
      fi
      if [[ -z "$resolved_at" ]]; then
        fail "resolved_at is missing in resolved issue ${issue_base}"
      fi
      if [[ -z "$resolution_doc_field" ]]; then
        fail "resolution_doc is missing in resolved issue ${issue_base}"
      fi

      expected_resolution_base="RESOLUTION-${issue_base#ISSUE-}"
      resolution_file="$ISSUE_TRACKER_RESOLVED_DIR/${expected_resolution_base}"
      if [[ ! -f "$resolution_file" ]]; then
        fail "resolved issue ${issue_base} has no paired resolution doc: expected ${resolution_file}"
      fi

      if [[ -f "$ISSUE_TRACKER_RESOLVED_DIR/README.md" ]] && ! issue_index_row_present "$ISSUE_TRACKER_RESOLVED_DIR/README.md" "$issue_id"; then
        fail "docs/issues/resolved/README.md missing index row for ${issue_base}"
      fi
    done < <(find "$ISSUE_TRACKER_RESOLVED_DIR" -maxdepth 1 -type f -name 'ISSUE-*.md' | sort)

    while IFS= read -r resolution_file; do
      resolution_base="$(basename "$resolution_file")"
      expected_issue_base="ISSUE-${resolution_base#RESOLUTION-}"
      if [[ ! -f "$ISSUE_TRACKER_RESOLVED_DIR/${expected_issue_base}" ]]; then
        fail "resolution doc ${resolution_base} has no paired issue file: expected ${ISSUE_TRACKER_RESOLVED_DIR}/${expected_issue_base}"
      fi
    done < <(find "$ISSUE_TRACKER_RESOLVED_DIR" -maxdepth 1 -type f -name 'RESOLUTION-*.md' | sort)
  fi

  if [[ -s "$all_ids_file" ]]; then
    while IFS= read -r dup_id; do
      [[ -n "$dup_id" ]] && fail "issue id ${dup_id} exists in both docs/issues/current/ and docs/issues/resolved/ (or is duplicated)"
    done < <(sort "$all_ids_file" | uniq -d)
  fi

  rm -f "$all_ids_file"
}

# ============================================================================
# Release C of the plan: the terminal close-record
# gate, the unknown-key rejection, and the index-projection rule are STRICT-mode
# rules. Release A/B shipped them advisory-only behind CLOSE_RECORD_STRICT_PROMOTED;
# Release C makes the switch default ON (the mandatory strict gate). The named
# constant stays so the promotion can be audited: exporting CLOSE_RECORD_STRICT_PROMOTED
# empty recreates the advisory-only pre-C behavior for comparison, and a strict run
# never silently skips these rules again by default.
# ============================================================================

# Default ON since Release C. An empty value disables strict promotion (advisory-only,
# the Release A/B posture); any non-empty value is the promoted strict gate.
CLOSE_RECORD_STRICT_PROMOTED="${CLOSE_RECORD_STRICT_PROMOTED:-1}"

# Under a plain strict run these rules now RUN (the switch defaults ON) and `fail`
# emits [FAIL] exactly where Release A/B emitted [WARN]. The only way they are skipped
# is an explicit CLOSE_RECORD_STRICT_PROMOTED= (empty) export -- the auditable
# pre-C posture, retained for comparison, never the default.
gate_skipped_under_strict() {
  [[ "$MODE" == "strict" && -z "$CLOSE_RECORD_STRICT_PROMOTED" ]]
}

# Exact-match placeholder tokens for close-field values (PLAN v1.7): only a value that
# is EXACTLY one of these (after the block reader's trim) is a placeholder -- prefix or
# partial matching is forbidden, so "tbd later" and "none of the above" are real content.
# The legacy marker literal is the one exempt value: it is a truthful statement that the
# standard search protocol (references/task-state-contract.md) found no close-time record,
# so it passes rather than failing as a placeholder.
CLOSE_FIELD_PLACEHOLDERS=(tbd TBD n/a none 미정)
LEGACY_CLOSE_MARKER="legacy — no close-time record found"

is_close_field_placeholder() {
  local value="$1"
  local candidate
  [[ "$value" == "$LEGACY_CLOSE_MARKER" ]] && return 1
  for candidate in "${CLOSE_FIELD_PLACEHOLDERS[@]}"; do
    [[ "$value" == "$candidate" ]] && return 0
  done
  return 1
}

# Envelope-bounded non-empty check for close fields, mirroring check_field_non_empty
# (10-parse.sh:498) but reading the value with extract_field_block: the close-record
# gate must accept BOTH inline scalars AND nested-bullet blocks as non-empty (PLAN
# v1.7 [block-reader] signal: "close 필드 검사는 인라인 스칼라와 중첩 불릿 블록을 모두
# 비어 있지 않은 것으로 인정한다"). check_field_non_empty reads only the key's own line
# (extract_field_value), so a done task whose objective/acceptance_criteria is a
# nested-bullet block was wrongly read as empty. The failure message format is
# byte-identical to check_field_non_empty, so tests asserting on the messages are
# unaffected; the emitter name (the JSON-contract id, FUNCNAME[1]) legitimately becomes
# this helper's name. check_field_non_empty itself is untouched -- it keeps single-line
# semantics for the axis_*/title/status/orchestration fields that are inline by contract.
check_close_field_block_non_empty() {
  local file_path="$1"
  local key="$2"
  local label="$3"
  local value

  if ! field_key_present "$file_path" "$key"; then
    fail "${key} is missing in ${label}: $file_path"
    return 1
  fi

  value="$(extract_field_block "$file_path" "$key")"
  if [[ -z "$value" ]]; then
    fail "${key} is present but empty in ${label}: $file_path"
    return 1
  fi
  return 0
}

# The terminal close-record matrix (references/task-state-contract.md):
#   done            -> objective + acceptance_criteria + outcome required
#   superseded/cancelled -> objective + disposition required (outcome optional,
#                           never required, never injected)
#   planned/in_progress/blocked -> no close fields required
# The gate is a static invariant, not a transition: a file that is ALREADY done with
# empty close fields fails without any transition being observed. Every close-field
# read is envelope-bounded (extract_field_block), so a `- outcome:` under a `## Close-out`
# narrative heading is not in the envelope and never satisfies the gate.
check_terminal_close_record() {
  local task_file="$1"
  local task_ref="$2"
  local task_status_primary="$3"
  local outcome_value=""
  local disposition_value=""

  gate_skipped_under_strict && return 0

  case "$task_status_primary" in
    done)
      check_close_field_block_non_empty "$task_file" "objective" "done task" || true
      check_close_field_block_non_empty "$task_file" "acceptance_criteria" "done task" || true
      outcome_value="$(extract_field_block "$task_file" "outcome")"
      if [[ -z "$outcome_value" ]]; then
        fail "outcome is missing in done task ${task_ref}: the terminal close-record gate requires objective + acceptance_criteria + outcome (references/task-state-contract.md)"
      elif is_close_field_placeholder "$outcome_value"; then
        fail "outcome in done task ${task_ref} is the placeholder '${outcome_value}': record the actual close-time evidence (exact-match placeholders: ${CLOSE_FIELD_PLACEHOLDERS[*]}; the legacy marker '${LEGACY_CLOSE_MARKER}' is the only exemption)"
      fi
      ;;
    superseded|cancelled)
      check_close_field_block_non_empty "$task_file" "objective" "${task_status_primary} task" || true
      # disposition presence/non-empty is enforced by the disposition block in
      # validate_docs.sh with the same block reader (check_close_field_block_non_empty);
      # this rule only adds the placeholder gate on the value when one is present.
      # outcome is optional here and never checked, required, or injected.
      disposition_value="$(extract_field_block "$task_file" "disposition")"
      if [[ -n "$disposition_value" ]] && is_close_field_placeholder "$disposition_value"; then
        fail "disposition in ${task_status_primary} task ${task_ref} is the placeholder '${disposition_value}': record the actual close-time evidence (exact-match placeholders: ${CLOSE_FIELD_PLACEHOLDERS[*]}; the legacy marker '${LEGACY_CLOSE_MARKER}' is the only exemption)"
      fi
      ;;
  esac
  return 0
}

# The complete task dictionary (references/task-state-contract.md "Task dictionary
# template") plus the legacy-key classification table (PLAN v1.7 "Legacy-Key
# Classification"): preserve-classified keys are registered dictionary members and are
# never unknown. Rename-classified keys (plan_ref -> consumes_plan_ref, close_out_note ->
# outcome) are NOT in the dictionary until Release B migrates them, so they warn.
TASK_DICTIONARY_KEYS=(title objective acceptance_criteria outcome non_goals affected_modules interfaces_changed data_migrations test_scope risks risk_level consumes_plan_ref status disposition owner claimed_at due_date axis_why axis_where axis_verify resume_source_head resume_changed_files resume_checkpointed_at resume_state_revision resume_next_action resume_last_verified resume_blockers)
TASK_LEGACY_ALLOWED_KEYS=(last_updated decision_ref orchestration_ref reviewers)

# Envelope-bounded unknown-key rejection: only a complete-dictionary key that is NOT in
# the dictionary or the legacy classification is flagged. The scan walks the SAME
# envelope boundary every other rule uses (doc_lines_envelope on the fence-stripped
# copy), so fenced example keys and narrative-section keys (`verdict`, `pending`,
# `reason` below the first unfenced `##`) are never scanned. Nested `  - key:` lines
# are block content, not column-0 keys, and are skipped by the column-0 anchor.
check_unknown_task_keys() {
  local task_file="$1"
  local task_ref="$2"
  local line
  local key
  local is_known=0
  local candidate

  gate_skipped_under_strict && return 0

  fence_stripped_file "$task_file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^-\ ([A-Za-z_][A-Za-z0-9_]*): ]]; then
      key="${BASH_REMATCH[1]}"
      is_known=0
      for candidate in "${TASK_DICTIONARY_KEYS[@]}" "${TASK_LEGACY_ALLOWED_KEYS[@]}"; do
        if [[ "$key" == "$candidate" ]]; then
          is_known=1
          break
        fi
      done
      if (( ! is_known )); then
        fail "unknown task-dictionary key '${key}' in envelope of ${task_ref}: not in the task dictionary or the legacy classification table (references/task-state-contract.md)"
      fi
    fi
  done < <(doc_lines_envelope "$FENCE_STRIPPED_PATH")
  return 0
}

# The task-index ROW summary column, extracted from a row like
# `- TASK-x | done | summary`. The ref match carries a trailing space so a row for a
# LONGER ref (`- TASK-x-extra | ...`) never answers for `TASK-x`. The summary is
# everything after the SECOND UNESCAPED pipe: `\|` inside the summary is content, not a
# separator. Returns empty when the row has no summary column (fewer than two pipes) or
# no row at all -- an unreadable task-index (the permission-cascade corpus) yields no
# rows and therefore no findings.
task_index_row_summary() {
  local index_file="$1"
  local task_ref="$2"

  # The permission-cascade corpus ships a task-index.md that exists but is unreadable
  # (600 gm-owned); an unreadable index yields no rows and therefore no findings, and
  # must not abort the run under errexit.
  [[ -f "$index_file" && -r "$index_file" ]] || return 0
  fence_stripped_file "$index_file"
  awk -v ref="- ${task_ref} " '
    index($0, ref) == 1 {
      line = substr($0, length(ref) + 1)
      seen = 0
      len = length(line)
      out = ""
      for (i = 1; i <= len; i++) {
        c = substr(line, i, 1)
        prev = (i > 1) ? substr(line, i - 1, 1) : ""
        if (c == "|" && prev != "\\") {
          seen++
          if (seen == 2) { out = substr(line, i + 1); break }
        }
      }
      if (seen >= 2) { print out; exit }
    }
  ' "$FENCE_STRIPPED_PATH" 2>/dev/null || true
}

# Row summary vs stored-field projection (PLAN v1.7 "[index]" acceptance signal): a
# task-index row whose summary does not match the envelope projection of the task file's
# stored fields is flagged. Writer and validator both derive from the stored fields
# through the ONE shared implementation (task_index_projection_summary in
# codeguide_doc_lines.sh), so a row the garden just wrote can never disagree with this
# check -- a row written from CLI-passed text (the pre-fix `TASK_TITLE` bug) is exactly
# what this catches.
check_task_index_projection() {
  local task_file
  local task_ref
  local task_status
  local row_summary
  local projected

  gate_skipped_under_strict && return 0
  [[ -f "$TASK_DIR/task-index.md" ]] || return 0

  while IFS= read -r task_file; do
    task_ref="$(basename "$task_file")"
    task_ref="${task_ref%.md}"
    row_summary="$(task_index_row_summary "$TASK_DIR/task-index.md" "$task_ref")"
    [[ -n "$row_summary" ]] || continue
    # The row format carries a space after each `|` separator, so the extracted column
    # is trimmed before the byte comparison; the projection is already trimmed by its
    # canonicalizer, and a writer that escaped a pipe lands `\|` on both sides.
    row_summary="$(printf "%s" "$row_summary" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    task_status="$(unfenced_field_value "$task_file" "status")"
    task_status="${task_status%% *}"
    projected="$(task_index_projection_summary "$task_file" "$task_status")"
    if [[ "$row_summary" != "$projected" ]]; then
      fail "task-index row summary for ${task_ref} does not match the stored-field projection: row has '${row_summary}' but the envelope projects '${projected}' (references/task-state-contract.md)"
    fi
  done < <(find "$TASK_DIR" -maxdepth 1 -type f -name 'TASK-*.md' | sort)
  return 0
}
