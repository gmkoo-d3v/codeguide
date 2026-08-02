#!/usr/bin/env bash
# validate_docs.d/40-rules-orchestration.sh — Orchestration rules: ORCH capsule checks, contradictions, evaluator-report gates, external-review await gates.
# Sourced by validate_docs.sh after CLI/global setup; not executable alone.
# Split from validate_docs.sh (behavior-preserving; function bodies verbatim).

risk_level_requires_adversarial() {
  local value="$1"
  [[ "$value" == "high" || "$value" == "critical" ]]
}

normalize_risk_level_value() {
  local value="$1"
  if [[ "$value" == "low | medium | high | critical" ]]; then
    printf ""
    return
  fi
  printf "%s" "$value"
}

adversarial_requirement_source_for_task() {
  local task_id="$1"
  local task_file="$TASK_DIR/TASK-${task_id}.md"
  local task_risk_level
  local decision_file
  local linked_task
  local decision_status
  local decision_risk_level
  local decision_base

  if [[ -f "$task_file" ]]; then
    task_risk_level="$(normalize_risk_level_value "$(extract_field_value "$task_file" "risk_level")")"
    if risk_level_requires_adversarial "$task_risk_level"; then
      printf "task risk_level=%s" "$task_risk_level"
      return
    fi
  fi

  if [[ ! -d "$DECISIONS_DIR" ]]; then
    return
  fi

  while IFS= read -r decision_file; do
    linked_task="$(extract_field_value "$decision_file" "linked_task")"
    [[ "$linked_task" == "TASK-${task_id}" ]] || continue

    decision_status="$(extract_field_value "$decision_file" "status")"
    [[ "$decision_status" == "superseded" ]] && continue

    decision_risk_level="$(normalize_risk_level_value "$(extract_field_value "$decision_file" "risk_level")")"
    if risk_level_requires_adversarial "$decision_risk_level"; then
      decision_base="$(basename "$decision_file")"
      printf "%s risk_level=%s" "$decision_base" "$decision_risk_level"
      return
    fi
  done < <(find "$DECISIONS_DIR" -maxdepth 1 -type f -name 'decision-*.md' ! -name 'decision-template.md' ! -name 'decision-index.md' | sort)
}

check_orchestration_file_for_task() {
  local task_id="$1"
  local task_ref="$2"
  local task_status="${3:-}"
  local orchestration_file
  local execution_mode
  local delegation_status
  local doc_task_id
  local primary_author_tool
  local review_mode
  local external_review_status
  local external_review_required_for
  local risk_preflight_status
  local risk_preflight_recorded_by
  local approval_required
  local approval_ref
  local approved_next_step
  local risk_preflight_recorded_by_normalized

  orchestration_file="$(codeguide_orchestration_file "$PROJECT_ROOT_ABS" "$task_id")"

  if [[ ! -f "$orchestration_file" ]]; then
    fail "missing orchestration file for active task ${task_ref}: expected ${orchestration_file}"
    return
  fi

  pass "orchestration file exists for active task ${task_ref}"
  # Size caps gate active authorship; a terminal task's capsule is immutable
  # evidence and is not re-measured against caps introduced later.
  if is_terminal_task_status "$task_status"; then
    pass "orchestration size cap skipped for terminal task artifact (status=${task_status}): ${orchestration_file}"
  else
    check_line_limit "$orchestration_file" "$MAX_ORCHESTRATION_LINES" "orchestration document"
  fi

  if [[ "$MODE" == "strict" ]]; then
    check_field_non_empty "$orchestration_file" "task_id" "orchestration" || true
    check_field_non_empty "$orchestration_file" "execution_mode" "orchestration" || true
    check_field_exists "$orchestration_file" "primary_author_tool" "orchestration" || true
    check_field_exists "$orchestration_file" "review_mode" "orchestration" || true
    check_field_non_empty "$orchestration_file" "supervisor_agent" "orchestration" || true
    check_field_non_empty "$orchestration_file" "delegation_status" "orchestration" || true
    check_field_non_empty "$orchestration_file" "risk_preflight_status" "orchestration" || true
    check_field_non_empty "$orchestration_file" "risk_preflight_recorded_by" "orchestration" || true
    check_field_non_empty "$orchestration_file" "risk_preflight_summary" "orchestration" || true
    check_field_non_empty "$orchestration_file" "approval_required" "orchestration" || true
    check_field_non_empty "$orchestration_file" "approval_ref" "orchestration" || true
    check_field_non_empty "$orchestration_file" "approved_next_step" "orchestration" || true
    check_field_non_empty "$orchestration_file" "last_updated" "orchestration" || true
  else
    check_field_exists "$orchestration_file" "task_id" "orchestration" || true
    check_field_exists "$orchestration_file" "execution_mode" "orchestration" || true
    check_field_exists "$orchestration_file" "primary_author_tool" "orchestration" || true
    check_field_exists "$orchestration_file" "review_mode" "orchestration" || true
    check_field_exists "$orchestration_file" "supervisor_agent" "orchestration" || true
    check_field_exists "$orchestration_file" "delegation_status" "orchestration" || true
    check_field_exists "$orchestration_file" "risk_preflight_status" "orchestration" || true
    check_field_exists "$orchestration_file" "risk_preflight_recorded_by" "orchestration" || true
    check_field_exists "$orchestration_file" "risk_preflight_summary" "orchestration" || true
    check_field_exists "$orchestration_file" "approval_required" "orchestration" || true
    check_field_exists "$orchestration_file" "approval_ref" "orchestration" || true
    check_field_exists "$orchestration_file" "approved_next_step" "orchestration" || true
    check_field_exists "$orchestration_file" "last_updated" "orchestration" || true
  fi

  doc_task_id="$(extract_field_value "$orchestration_file" "task_id")"
  if [[ -n "$doc_task_id" && "$doc_task_id" != "$task_id" ]]; then
    fail "task_id mismatch in orchestration for ${task_ref}: ${doc_task_id} != ${task_id}"
  fi

  execution_mode="$(extract_field_value "$orchestration_file" "execution_mode")"
  primary_author_tool="$(extract_field_value "$orchestration_file" "primary_author_tool")"
  review_mode="$(extract_field_value "$orchestration_file" "review_mode")"
  external_review_status="$(extract_field_value "$orchestration_file" "external_review_status")"
  external_review_required_for="$(extract_field_value "$orchestration_file" "external_review_required_for")"
  delegation_status="$(extract_field_value "$orchestration_file" "delegation_status")"
  risk_preflight_status="$(extract_field_value "$orchestration_file" "risk_preflight_status")"
  risk_preflight_recorded_by="$(extract_field_value "$orchestration_file" "risk_preflight_recorded_by")"
  approval_required="$(extract_field_value "$orchestration_file" "approval_required")"
  approval_ref="$(extract_field_value "$orchestration_file" "approval_ref")"
  approved_next_step="$(extract_field_value "$orchestration_file" "approved_next_step")"
  check_enum_membership "$execution_mode" "orchestration.execution_mode" "$orchestration_file" supervisor_subagents solo || true
  check_enum_membership "$primary_author_tool" "orchestration.primary_author_tool" "$orchestration_file" antigravity agy claude codex human external-runner || true
  check_enum_membership "$review_mode" "orchestration.review_mode" "$orchestration_file" external_cli current_task_debate agy_subagents claude_subagents codex_subagents || true
  if [[ -n "$external_review_status" ]]; then
    check_enum_membership "$external_review_status" "orchestration.external_review_status" "$orchestration_file" not_requested requested running awaiting_response ingested blocked waived || true
  fi
  if [[ -n "$external_review_required_for" ]]; then
    check_enum_membership "$external_review_required_for" "orchestration.external_review_required_for" "$orchestration_file" plan_acceptance implementation_start commit close || true
  fi
  check_enum_membership "$delegation_status" "orchestration.delegation_status" "$orchestration_file" planned active completed blocked || true
  check_enum_membership "$risk_preflight_status" "orchestration.risk_preflight_status" "$orchestration_file" pass approved blocked approval_required || true
  check_enum_membership "$approval_required" "orchestration.approval_required" "$orchestration_file" true false || true

  risk_preflight_recorded_by_normalized="$(printf "%s" "$risk_preflight_recorded_by" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$risk_preflight_recorded_by_normalized" in
    antigravity|agy|claude|codex|gemini|external-runner|external-review-wrapper|external-cli*)
      fail "orchestration risk_preflight_recorded_by must identify the main-thread supervising lead architect, not evaluator/tool identity: ${orchestration_file}"
      ;;
  esac

  if [[ "$risk_preflight_status" == "approved" && "$approval_required" != "true" ]]; then
    fail "orchestration risk_preflight_status=approved requires approval_required=true: ${orchestration_file}"
  fi
  if [[ "$risk_preflight_status" == "approval_required" && "$approval_required" != "true" ]]; then
    fail "orchestration risk_preflight_status=approval_required requires approval_required=true: ${orchestration_file}"
  fi
  if [[ "$risk_preflight_status" == "pass" && "$approval_required" != "false" ]]; then
    fail "orchestration risk_preflight_status=pass requires approval_required=false: ${orchestration_file}"
  fi
  if [[ "$risk_preflight_status" == "blocked" && "$approval_required" != "false" ]]; then
    fail "orchestration risk_preflight_status=blocked requires approval_required=false: ${orchestration_file}"
  fi
  if [[ "$approval_required" == "true" && "$risk_preflight_status" != "approved" && "$risk_preflight_status" != "approval_required" ]]; then
    fail "orchestration approval_required=true requires risk_preflight_status=approved or approval_required: ${orchestration_file}"
  fi
  if [[ "$risk_preflight_status" == "approved" ]]; then
    if is_placeholder_approval_value "$approval_ref"; then
      fail "orchestration approved preflight requires a concrete approval_ref: ${orchestration_file}"
    fi
    if is_placeholder_approval_value "$approved_next_step"; then
      fail "orchestration approved preflight requires approved_next_step: ${orchestration_file}"
    fi
  fi
  if [[ "$review_mode" == "external_cli" && "$risk_preflight_status" != "approved" ]]; then
    fail "orchestration review_mode=external_cli requires risk_preflight_status=approved with concrete approval provenance: ${orchestration_file}"
  fi

  if [[ "$execution_mode" != "solo" || "$review_mode" == "external_cli" || "$review_mode" == "current_task_debate" || "$review_mode" == "agy_subagents" || "$review_mode" == "claude_subagents" || "$review_mode" == "codex_subagents" ]]; then
    if [[ "$MODE" == "strict" ]]; then
      check_field_non_empty "$orchestration_file" "primary_author_tool" "orchestration" || true
      check_field_non_empty "$orchestration_file" "review_mode" "orchestration" || true
    fi
    if [[ "$risk_preflight_status" == "blocked" || "$risk_preflight_status" == "approval_required" ]]; then
      fail "orchestration risk preflight must be pass or approved before delegated/external review: ${orchestration_file}"
    fi
  fi

  if [[ "$execution_mode" == "solo" ]]; then
    if [[ "$MODE" == "strict" ]]; then
      check_field_non_empty "$orchestration_file" "delegation_note" "orchestration" || true
    else
      check_field_exists "$orchestration_file" "delegation_note" "orchestration" || true
    fi
    return
  fi

  if [[ "$MODE" == "strict" ]]; then
    check_field_non_empty "$orchestration_file" "planner_agents" "orchestration" || true
    check_field_non_empty "$orchestration_file" "reviewer_agents" "orchestration" || true
    check_field_non_empty "$orchestration_file" "implementation_agents" "orchestration" || true
    check_field_non_empty "$orchestration_file" "validation_agents" "orchestration" || true
    check_field_non_empty "$orchestration_file" "owned_scopes" "orchestration" || true
  else
    check_field_exists "$orchestration_file" "planner_agents" "orchestration" || true
    check_field_exists "$orchestration_file" "reviewer_agents" "orchestration" || true
    check_field_exists "$orchestration_file" "implementation_agents" "orchestration" || true
    check_field_exists "$orchestration_file" "validation_agents" "orchestration" || true
    check_field_exists "$orchestration_file" "owned_scopes" "orchestration" || true
  fi
}

# ORCH semantic-contradiction checks (advisory warning tier -- gated by
# MODE != strict, the same "recommended" tier as the concurrent-session claim
# contract's owner/claimed_at/claim-directory fields, so it never promotes to
# a strict-mode failure). Flags internally self-contradictory ORCH capsules
# regardless of whether the owning task is currently "active": a capsule can
# drift into a contradictory state on a blocked/done task just as easily as
# an in_progress one, and the per-active-task checks above do not cover that.
check_orchestration_semantic_contradictions() {
  local orchestration_file="$1"
  local orch_ref="$2"
  local task_file="${3:-}"
  local execution_mode
  local delegation_status
  local external_review_status
  local required_review_routes
  local external_review_result_ref
  local task_status
  local agent_key
  local has_agent_field="false"

  delegation_status="$(extract_field_value "$orchestration_file" "delegation_status")"

  # Cross-artifact coherence runs in BOTH modes (promoted per
  # quality-baseline review r01 C1): a capsule claiming planned/active
  # delegation while its task ledger says the work is closed is a
  # ledger-integrity defect, not a style nit, and must keep strict red.
  if [[ -n "$task_file" && -f "$task_file" ]]; then
    task_status="$(extract_field_value "$task_file" "status")"
    task_status="${task_status%% *}"
    if [[ "$task_status" == "done" && ( "$delegation_status" == "active" || "$delegation_status" == "planned" ) ]]; then
      fail "orchestration delegation_status '${delegation_status}' contradicts task status done for ${orch_ref}: ${orchestration_file}"
    fi
    if [[ "$task_status" == "blocked" && "$delegation_status" == "active" ]]; then
      fail "orchestration delegation_status 'active' contradicts task status blocked for ${orch_ref}: ${orchestration_file}"
    fi
    if [[ ( "$task_status" == "superseded" || "$task_status" == "cancelled" ) && ( "$delegation_status" == "active" || "$delegation_status" == "planned" ) ]]; then
      fail "orchestration delegation_status '${delegation_status}' contradicts terminal task status ${task_status} for ${orch_ref}: ${orchestration_file}"
    fi
  fi

  if [[ "$MODE" == "strict" ]]; then
    return 0
  fi

  execution_mode="$(extract_field_value "$orchestration_file" "execution_mode")"
  for agent_key in planner_agents reviewer_agents implementation_agents validation_agents; do
    if [[ -n "$(extract_field_value "$orchestration_file" "$agent_key")" ]]; then
      has_agent_field="true"
      break
    fi
  done
  if [[ "$execution_mode" == "supervisor_subagents" ]]; then
    if [[ "$has_agent_field" != "true" ]]; then
      fail "orchestration execution_mode=supervisor_subagents requires at least one non-empty agent field (planner_agents/reviewer_agents/implementation_agents/validation_agents) for ${orch_ref}: ${orchestration_file}"
    fi
    if [[ -z "$delegation_status" ]]; then
      fail "orchestration execution_mode=supervisor_subagents requires a non-empty delegation_status for ${orch_ref}: ${orchestration_file}"
    fi
  fi
  # The converse contradiction: a solo declaration alongside named delegated
  # agents suppresses solo-exempt checks (fable P3-r01 finding 2 — the false
  # solo hid a review-pending warning behind the exemption).
  if [[ "$execution_mode" == "solo" && "$has_agent_field" == "true" ]]; then
    fail "orchestration execution_mode=solo contradicts non-empty delegated agent fields for ${orch_ref}: ${orchestration_file}"
  fi

  # Enum validation for every capsule (the per-active-task checks below only
  # reach capsules of active tasks, so a corrupted value on a planned-task
  # capsule would otherwise be invisible).
  if [[ -n "$delegation_status" ]]; then
    check_enum_membership "$delegation_status" "orchestration.delegation_status" "$orchestration_file" planned active completed blocked || true
  fi

  external_review_status="$(extract_field_value "$orchestration_file" "external_review_status")"
  if [[ "$external_review_status" == "ingested" ]]; then
    required_review_routes="$(extract_field_value "$orchestration_file" "required_review_routes")"
    external_review_result_ref="$(extract_field_value "$orchestration_file" "external_review_result_ref")"
    if [[ -z "$required_review_routes" ]]; then
      fail "orchestration external_review_status=ingested requires a non-empty required_review_routes for ${orch_ref}: ${orchestration_file}"
    fi
    if [[ -z "$external_review_result_ref" ]]; then
      fail "orchestration external_review_status=ingested requires a non-empty external_review_result_ref for ${orch_ref}: ${orchestration_file}"
    fi
  fi
}

# tmp/ path reference detection (advisory warning tier -- gated by
# MODE != strict, same rationale as check_orchestration_semantic_contradictions
# above): scans only durable, authored docs -- docs/task/*.md, docs/plan/*.md,
# and docs/orchestration/*/{INDEX.md,ORCH.md} -- for `codeguide/tmp/` or
# `/tmp/` path references. Deliberately does NOT touch docs/report/* or any
# external-cli *.response.md payload: external tool responses legitimately
# quote arbitrary filesystem paths that are not durable-doc references. Skips
# fenced code examples using the same fence-aware idiom as extract_shadow_field.
# One awk pass over the whole file list, not two process substitutions per file:
# on bash 3.2 (stock macOS) the per-file nested form corrupted the shell heap and
# killed the run with a fatal signal in a later phase once a corpus exceeded a
# handful of task files. `FNR == 1`
# resets the fence state at each file boundary, so fence handling stays per-file.
check_tmp_path_references() {
  local finding

  while IFS= read -r finding; do
    [[ -z "$finding" ]] && continue
    case "$finding" in
      "tmp "*) fail "docs reference a gitignored tmp/ path (${finding#tmp })" ;;
      # Dangling archive references: the no-archive policy deletes _archive
      # directories, so any surviving path reference into one is a broken link.
      "arc "*) fail "docs reference a deleted _archive path (${finding#arc })" ;;
    esac
  done < <(
    {
      find "$TASK_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null
      find "$PLAN_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null
      find "$ORCHESTRATION_DIR" -mindepth 2 -maxdepth 2 -type f \( -name 'INDEX.md' -o -name 'ORCH.md' \) 2>/dev/null
    } | sort | tr '\n' '\0' | xargs -0 awk '
      FNR == 1 { infence = 0 }
      /^[[:space:]]*(```|~~~)/ { infence = !infence; next }
      infence { next }
      /codeguide\/tmp\// { printf "tmp %s:%d\n", FILENAME, FNR; next }
      /(^|[^A-Za-z0-9_.-])\/tmp\// { printf "tmp %s:%d\n", FILENAME, FNR; next }
      /docs\/(plan|task|orchestration)\/_archive\// { printf "arc %s:%d\n", FILENAME, FNR }
    ' 2>/dev/null
  )
}

orchestration_execution_mode_for_task() {
  local task_id="$1"
  local orchestration_file

  orchestration_file="$(codeguide_orchestration_file "$PROJECT_ROOT_ABS" "$task_id")"

  if [[ ! -f "$orchestration_file" ]]; then
    return
  fi

  extract_field_value "$orchestration_file" "execution_mode"
}

latest_plan_version_for_task() {
  local task_id="$1"
  local plan_file
  local plan_base
  local version
  local major
  local minor
  local best_major=-1
  local best_minor=-1
  local best_version=""

  while IFS= read -r plan_file; do
    plan_base="$(basename "$plan_file")"
    version="$(printf "%s" "$plan_base" | sed -E 's/^PLAN-.*-(v[0-9]+\.[0-9]+)\.md$/\1/')"
    [[ "$version" =~ ^v[0-9]+\.[0-9]+$ ]] || continue
    major="${version#v}"
    major="${major%%.*}"
    minor="${version##*.}"
    major=$((10#$major))
    minor=$((10#$minor))
    if (( major > best_major || (major == best_major && minor > best_minor) )); then
      best_major="$major"
      best_minor="$minor"
      best_version="$version"
    fi
  done < <(find "$PLAN_DIR" -maxdepth 1 -type f -name "PLAN-${task_id}-v*.md" ! -name 'PLAN-template.md' | sort)

  printf "%s" "$best_version"
}

check_evaluator_reports_for_task() {
  local task_id="$1"
  local task_ref="$2"
  local execution_mode="$3"
  local adversarial_source="${4:-}"
  local latest_plan_version="${5:-}"
  local task_status="${6:-}"
  local report_count=0
  local adversarial_count=0
  local stale_report_count=0
  local report_file
  local report_review_style
  local expected_report_glob
  local report_base
  local report_task_id
  local report_plan_version
  local report_evaluator
  local report_round
  local file_report_task_id
  local file_evaluator
  local file_round
  local plan_file
  local report_epoch
  local plan_epoch

  if [[ -z "$latest_plan_version" ]]; then
    latest_plan_version="$(latest_plan_version_for_task "$task_id")"
  fi
  if [[ -z "$latest_plan_version" ]]; then
    fail "cannot determine latest plan version for active task ${task_ref}"
    return
  fi

  # A done task was gated on the plan it consumed when it closed; plan versions
  # added after close (post-review records, next-round notes) must not reopen
  # the gate retroactively. Lineage rule: at least one identity-valid evaluator
  # report for ANY plan version of this task. Reports whose filename and fields
  # disagree are skipped here — the global report loop already fails them.
  # in_progress/blocked tasks keep the fresh latest-plan gate below.
  if [[ "$task_status" == "done" ]]; then
    while IFS= read -r report_file; do
      report_base="$(basename "$report_file")"
      parse_evaluator_report_filename "$report_base" || continue
      [[ "$REPORT_FILE_TASK_ID" == "$task_id" ]] || continue
      # A lineage report only counts when the plan version it names actually
      # exists (review r01 C2): a report against a phantom version must not
      # satisfy the gate on its own.
      [[ -f "$PLAN_DIR/PLAN-${task_id}-${REPORT_FILE_PLAN_VERSION}.md" ]] || continue
      report_task_id="$(extract_field_value "$report_file" "task_id")"
      report_plan_version="$(extract_field_value "$report_file" "plan_version")"
      report_evaluator="$(extract_field_value "$report_file" "evaluator")"
      report_round="$(extract_field_value "$report_file" "review_round")"
      if [[ "$report_task_id" != "$task_id" || "$report_plan_version" != "$REPORT_FILE_PLAN_VERSION" || "$report_evaluator" != "$REPORT_FILE_EVALUATOR" || "$report_round" != "$REPORT_FILE_ROUND" ]]; then
        continue
      fi
      report_count=$((report_count + 1))
      report_review_style="$(extract_field_value "$report_file" "review_style")"
      if [[ "$report_review_style" == "adversarial" ]]; then
        adversarial_count=$((adversarial_count + 1))
      fi
    done < <(find "$REPORT_DIR" -maxdepth 1 -type f -name "PLAN-${task_id}-v*-review-*.md" | sort)

    if [[ -n "$adversarial_source" ]]; then
      if (( adversarial_count > 0 )); then
        pass "adversarial evaluator report exists in plan lineage for done high-risk task ${task_ref} (${adversarial_count})"
      else
        fail "missing adversarial evaluator report in plan lineage for done high-risk task ${task_ref} (${adversarial_source}): expected ${REPORT_DIR}/PLAN-${task_id}-v*-review-<runner>-<model-slug>-rNN.md with review_style: adversarial"
      fi
      return
    fi
    if [[ "$execution_mode" == "solo" ]]; then
      pass "evaluator reports optional for solo execution on ${task_ref}"
      return
    fi
    if (( report_count > 0 )); then
      pass "evaluator report exists in plan lineage for done task ${task_ref} (${report_count})"
    else
      fail "missing evaluator report in plan lineage for done task ${task_ref}: expected at least one ${REPORT_DIR}/PLAN-${task_id}-v*-review-<runner>-<model-slug>-rNN.md"
    fi
    return
  fi

  expected_report_glob="$REPORT_DIR/PLAN-${task_id}-${latest_plan_version}-review-*.md"
  plan_file="$PLAN_DIR/PLAN-${task_id}-${latest_plan_version}.md"
  if compgen -G "$expected_report_glob" >/dev/null; then
    while IFS= read -r report_file; do
      report_base="$(basename "$report_file")"
      if ! parse_evaluator_report_filename "$report_base"; then
        fail "evaluator report identity mismatch for active task gate: ${report_base}"
        continue
      fi
      file_report_task_id="$REPORT_FILE_TASK_ID"
      file_evaluator="$REPORT_FILE_EVALUATOR"
      file_round="$REPORT_FILE_ROUND"
      report_task_id="$(extract_field_value "$report_file" "task_id")"
      report_plan_version="$(extract_field_value "$report_file" "plan_version")"
      report_evaluator="$(extract_field_value "$report_file" "evaluator")"
      report_round="$(extract_field_value "$report_file" "review_round")"

      if [[ "$file_report_task_id" != "$task_id" || "$report_task_id" != "$task_id" || "$report_plan_version" != "$latest_plan_version" || "$report_evaluator" != "$file_evaluator" || "$report_round" != "$file_round" ]]; then
        fail "evaluator report identity mismatch for active task gate: ${report_base}"
        continue
      fi

      if [[ -f "$plan_file" ]]; then
        report_epoch="$(file_effective_epoch "$report_file")"
        plan_epoch="$(file_effective_epoch "$plan_file")"
        if (( report_epoch < plan_epoch )); then
          stale_report_count=$((stale_report_count + 1))
          continue
        fi
      fi

      report_count=$((report_count + 1))
      report_review_style="$(extract_field_value "$report_file" "review_style")"
      if [[ "$report_review_style" == "adversarial" ]]; then
        adversarial_count=$((adversarial_count + 1))
      fi
    done < <(find "$REPORT_DIR" -maxdepth 1 -type f -name "PLAN-${task_id}-${latest_plan_version}-review-*.md" | sort)
  fi

  if [[ -n "$adversarial_source" ]]; then
    if (( adversarial_count > 0 )); then
      pass "adversarial evaluator report exists for high-risk task ${task_ref} latest plan ${latest_plan_version} (${adversarial_count})"
    else
      fail "missing adversarial evaluator report for high-risk task ${task_ref} latest plan ${latest_plan_version} (${adversarial_source}): expected ${REPORT_DIR}/PLAN-${task_id}-${latest_plan_version}-review-<runner>-<model-slug>-rNN.md with review_style: adversarial"
    fi
    return
  fi

  if [[ "$execution_mode" == "solo" ]]; then
    pass "evaluator reports optional for solo execution on ${task_ref}"
    return
  fi

  if (( report_count > 0 )); then
    pass "evaluator report exists for active task ${task_ref} latest plan ${latest_plan_version} (${report_count})"
  elif (( stale_report_count > 0 )); then
    fail "missing fresh evaluator report for active task ${task_ref} latest plan ${latest_plan_version}: ${stale_report_count} stale report(s) ignored"
  else
    fail "missing evaluator report for active task ${task_ref} latest plan ${latest_plan_version}: expected ${REPORT_DIR}/PLAN-${task_id}-${latest_plan_version}-review-<runner>-<model-slug>-rNN.md"
  fi
}

await_gate_route_has_accept_artifact() {
  local result_dir="$1"
  local route="$2"
  local slug
  local candidate
  local verdict

  slug="$(route_slug_for_filename "$route")"
  for candidate in "$result_dir/${slug}.response.md" "$result_dir/${slug}.retry-response.md"; do
    if [[ ! -f "$candidate" ]]; then
      continue
    fi
    verdict="$(extract_field_value "$candidate" "verdict")"
    if [[ "$verdict" == "accept" ]]; then
      return 0
    fi
  done

  return 1
}

parse_required_review_routes_for_await_gate() {
  local raw_routes="$1"
  local route
  local normalized
  local seen_routes="|"
  local parsed_count=0

  AWAIT_GATE_ROUTES=()
  if is_placeholder_approval_value "$raw_routes"; then
    fail "external review await gate requires non-empty required_review_routes"
    return 1
  fi

  IFS=',' read -r -a AWAIT_GATE_RAW_ROUTES <<< "$raw_routes"
  for route in "${AWAIT_GATE_RAW_ROUTES[@]}"; do
    normalized="$(trim_value "$route")"
    if [[ -z "$normalized" ]]; then
      fail "external review await gate required_review_routes contains an empty route member"
      return 1
    fi
    if [[ "$seen_routes" == *"|${normalized}|"* ]]; then
      fail "external review await gate required_review_routes contains duplicate route: ${normalized}"
      return 1
    fi
    if ! is_registry_colon_route "$normalized"; then
      fail "external review await gate required_review_routes must use registered colon route: ${normalized}"
      return 1
    fi
    seen_routes="${seen_routes}${normalized}|"
    AWAIT_GATE_ROUTES+=("$normalized")
    parsed_count=$((parsed_count + 1))
  done

  if (( parsed_count == 0 )); then
    fail "external review await gate requires non-empty required_review_routes"
    return 1
  fi
  return 0
}

check_ingested_external_review_await_gate() {
  local task_id="$1"
  local consumes_plan_ref="$2"
  local consumed_plan_version="$3"
  local orchestration_file="$4"
  local required_review_routes
  local review_round
  local result_ref
  local result_dir
  local result_dir_physical
  local expected_dir
  local expected_dir_physical
  local route

  required_review_routes="$(extract_field_value "$orchestration_file" "required_review_routes")"
  if ! parse_required_review_routes_for_await_gate "$required_review_routes"; then
    return
  fi

  review_round="$(extract_field_value "$orchestration_file" "external_review_round")"
  if [[ ! "$review_round" =~ ^r[0-9][0-9]$ ]]; then
    fail "external review await gate requires external_review_round rNN for ${consumes_plan_ref}"
    return
  fi

  result_ref="$(extract_field_value "$orchestration_file" "external_review_result_ref")"
  if is_placeholder_approval_value "$result_ref"; then
    fail "external review await gate requires external_review_result_ref directory for ${consumes_plan_ref}"
    return
  fi

  result_dir="$(resolve_docs_ref_path "$result_ref")"
  if [[ ! -d "$result_dir" ]]; then
    fail "external review await gate result_ref directory missing or not a directory: ${result_ref}"
    return
  fi

  expected_dir="$(codeguide_external_cli_dir "$PROJECT_ROOT_ABS" "$task_id" "$consumed_plan_version" "$review_round")"
  result_dir_physical="$(cd "$result_dir" && pwd -P)"
  if [[ -d "$expected_dir" ]]; then
    expected_dir_physical="$(cd "$expected_dir" && pwd -P)"
  else
    expected_dir_physical="$expected_dir"
  fi
  if [[ "$result_dir_physical" != "$expected_dir_physical" ]]; then
    fail "external review await gate result_ref must match consumed plan version and round: ${result_ref} != ${expected_dir}"
    return
  fi

  for route in "${AWAIT_GATE_ROUTES[@]}"; do
    if ! await_gate_route_has_accept_artifact "$result_dir_physical" "$route"; then
      fail "external review await gate missing accepted route artifact for ${route} under ${result_ref}"
      return
    fi
  done

  pass "external review await gate satisfied for ${consumes_plan_ref}"
}

check_waived_external_review_await_gate() {
  local orchestration_file="$1"
  local waiver_ref
  local waiver_reason

  waiver_ref="$(extract_field_value "$orchestration_file" "external_review_waiver_ref")"
  waiver_reason="$(extract_field_value "$orchestration_file" "external_review_waiver_reason")"
  if is_placeholder_approval_value "$waiver_ref" || is_placeholder_approval_value "$waiver_reason"; then
    fail "external review await gate waiver requires concrete external_review_waiver_ref and external_review_waiver_reason"
    return
  fi

  pass "external review await gate waived with concrete provenance"
}

check_external_review_await_gate_for_task() {
  local task_id="$1"
  local task_ref="$2"
  local task_file="$3"
  local task_status="$4"
  local orchestration_file
  local required_for
  local consumes_plan_ref
  local consumed_plan_version
  local status

  [[ "$MODE" == "advisory" ]] || return 0
  [[ "$task_status" == "in_progress" || "$task_status" == "done" ]] || return 0

  orchestration_file="$(codeguide_orchestration_file "$PROJECT_ROOT_ABS" "$task_id")"
  [[ -f "$orchestration_file" ]] || return 0

  required_for="$(extract_field_value "$orchestration_file" "external_review_required_for")"
  [[ "$required_for" == "implementation_start" ]] || return 0

  consumes_plan_ref="$(extract_field_value "$task_file" "consumes_plan_ref")"
  if [[ "$consumes_plan_ref" != PLAN-"${task_id}"-v* ]]; then
    fail "external review await gate requires same-task consumes_plan_ref for ${task_ref}"
    return
  fi
  consumed_plan_version="${consumes_plan_ref#PLAN-${task_id}-}"
  if [[ ! "$consumed_plan_version" =~ ^v[0-9]+\.[0-9]+$ ]]; then
    fail "external review await gate requires same-task consumes_plan_ref for ${task_ref}"
    return
  fi
  if [[ ! -f "$PLAN_DIR/${consumes_plan_ref}.md" ]]; then
    fail "external review await gate consumes_plan_ref points to missing plan: ${consumes_plan_ref}"
    return
  fi

  status="$(extract_field_value "$orchestration_file" "external_review_status")"
  case "$status" in
    ingested)
      check_ingested_external_review_await_gate "$task_id" "$consumes_plan_ref" "$consumed_plan_version" "$orchestration_file"
      ;;
    waived)
      check_waived_external_review_await_gate "$orchestration_file"
      ;;
    "")
      fail "external review await gate requires external_review_status for ${task_ref}"
      ;;
    not_requested|requested|running|awaiting_response|blocked)
      fail "external review await gate not satisfied for ${task_ref}: external_review_status=${status}"
      ;;
    *)
      fail "external review await gate has invalid external_review_status for ${task_ref}: ${status}"
      ;;
  esac
  return 0
}
