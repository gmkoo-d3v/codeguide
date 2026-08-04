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

  all_refs_file="$(mktemp)"

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

  all_ids_file="$(mktemp)"

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
