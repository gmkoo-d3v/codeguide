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
# fenced code examples.
#
# The fence rule below is the CommonMark one the shared reader implements (see
# `content_lines` in scripts, the recorded decision): a block closes only
# on a marker of the SAME character and at least the length of the opener, and this
# awk is asserted equal to it by test. It used to toggle on ANY marker, which is the
# exact bug the recorded decision exists to end and which
# extract_shadow_field is on record as having escaped -- a `~~~` line inside a
# ``` example flipped the state, so this rule reported a gitignored `/tmp/` path
# on a line the shared reader sees as fence content, and would have missed a real
# reference in the mirror case (the task r02 finding 8,
# reproduced). It stays awk rather than delegating: it must scan the whole file
# list in ONE pass, and the fence-stripped cache is keyed per file, so consuming
# it here would mean a spawn or a re-read per document.
#
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
      FNR == 1 { infence = 0; fchar = ""; flen = 0 }
      /^[[:space:]]*(```|~~~)/ {
        # Same rule as the shared reader: remember which character
        # opened the block and how long the run was, and close only on a marker
        # of that character with at least that length. A shorter or different
        # marker inside the block is content, not a closer.
        marker = $0
        sub(/^[[:space:]]*/, "", marker)
        mchar = substr(marker, 1, 1)
        mlen = 0
        while (substr(marker, mlen + 1, 1) == mchar) { mlen++ }
        if (infence == 0) { infence = 1; fchar = mchar; flen = mlen }
        else if (mchar == fchar && mlen >= flen) { infence = 0; fchar = ""; flen = 0 }
        next
      }
      infence { next }
      {
        # The two classes are INDEPENDENT: one line can reference both a tmp/
        # path and a dead _archive path, and it must report both. The pre-fix
        # code got that right by scanning the file twice; collapsing to one pass
        # with `next` between the rules silently dropped the second finding
        # (caught by the independent audit of the tracked issue).
        # Within the tmp class the two patterns overlap, so guard that one with a flag.
        tmp_hit = 0
        if ($0 ~ /codeguide\/tmp\//) { tmp_hit = 1 }
        else if ($0 ~ /(^|[^A-Za-z0-9_.-])\/tmp\//) { tmp_hit = 1 }
        if (tmp_hit) { printf "tmp %s:%d\n", FILENAME, FNR }
        if ($0 ~ /docs\/(plan|task|orchestration)\/_archive\//) { printf "arc %s:%d\n", FILENAME, FNR }
      }
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

# Verifies the evidence set behind ONE required route. What counts as evidence (companion
# request, wrapper-generated provenance, SHA-256 of the response, task/plan/round/route
# coherence, review fields) lives in validate_docs_review_evidence.py; this wrapper only
# runs it. On rejection the reasons are left in AWAIT_GATE_EVIDENCE_REASON for the caller's
# message. $6 selects the tier: `full` (default) is the integrity check; `verdict` keeps
# the pre-hardening reading (any recognised response file saying `verdict: accept`) for
# terminal tasks only, whose closed evidence is immutable history and is not re-measured
# against rules introduced after they closed.
await_gate_route_has_accept_artifact() {
  local result_dir="$1"
  local route="$2"
  local task_id="$3"
  local plan_version="$4"
  local review_round="$5"
  local verify_tier="${6:-full}"
  local verify_args=()

  AWAIT_GATE_EVIDENCE_REASON=""
  if [[ "$verify_tier" == "verdict" ]]; then
    verify_args+=(--verdict-only)
  fi
  if AWAIT_GATE_EVIDENCE_REASON="$(python3 -I "$SCRIPT_DIR/validate_docs_review_evidence.py" ${verify_args[@]+"${verify_args[@]}"} "$result_dir" "$route" "$task_id" "$plan_version" "$review_round")"; then
    return 0
  fi
  # Fail closed on ANY non-zero exit, including a verifier that crashed (unreadable file,
  # missing interpreter): that is "could not verify", never "verified".
  AWAIT_GATE_EVIDENCE_REASON="$(printf '%s' "$AWAIT_GATE_EVIDENCE_REASON" | tr '\n' ';' | sed 's/;/; /g; s/; $//')"
  if [[ -z "$AWAIT_GATE_EVIDENCE_REASON" ]]; then
    AWAIT_GATE_EVIDENCE_REASON="the evidence verifier could not run to completion (see stderr)"
  fi
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

  IFS=',' read -r -a AWAIT_GATE_RAW_ROUTES < <(printf '%s\n' "$raw_routes")
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
    if ! await_gate_route_has_accept_artifact "$result_dir_physical" "$route" "$task_id" "$consumed_plan_version" "$review_round" "${AWAIT_GATE_VERIFY_TIER:-full}"; then
      if [[ "${AWAIT_GATE_VERIFY_TIER:-full}" == "verdict" ]]; then
        # The terminal-task tier keeps its historical message byte for byte (text output is a
        # frozen contract); only the full tier explains WHY the evidence was rejected.
        fail "external review await gate missing accepted route artifact for ${route} under ${result_ref}"
      else
        fail "external review await gate missing accepted route artifact for ${route} under ${result_ref}: ${AWAIT_GATE_EVIDENCE_REASON}"
      fi
      return
    fi
  done

  pass "external review await gate satisfied for ${consumes_plan_ref}"
}

# A waiver is a user decision (references/goal-loop-contract.md lists "waiver" among the
# user-decision gates), so its only legitimate backing is a durable user decision record. A
# non-placeholder STRING proves nothing -- any invented sentence satisfied the old guard --
# so the ref must resolve to a real docs/decisions/decision-<id>.md that is accepted,
# chosen by the user, and linked to THIS task (not another task's decision reused). The
# reason must still be concrete. Terminal tasks keep the pre-hardening string check (closed
# evidence is immutable history; see await_gate_route_has_accept_artifact).
check_waived_external_review_await_gate() {
  local orchestration_file="$1"
  local task_id="$2"
  local waiver_ref
  local waiver_reason
  local waiver_path
  local waiver_base
  local waiver_dir_physical
  local decisions_dir_physical
  local decision_status
  local decision_chosen_by
  local decision_linked_task
  local problems=""

  waiver_ref="$(extract_field_value "$orchestration_file" "external_review_waiver_ref")"
  waiver_reason="$(extract_field_value "$orchestration_file" "external_review_waiver_reason")"
  if is_placeholder_approval_value "$waiver_ref" || is_placeholder_approval_value "$waiver_reason"; then
    fail "external review await gate waiver requires concrete external_review_waiver_ref and external_review_waiver_reason"
    return
  fi

  if [[ "${AWAIT_GATE_VERIFY_TIER:-full}" == "verdict" ]]; then
    pass "external review await gate waived with concrete provenance"
    return
  fi

  waiver_path="$(resolve_docs_ref_path "$waiver_ref")"
  waiver_base="$(basename "$waiver_path")"
  if [[ ! -f "$waiver_path" || -L "$waiver_path" || ! -d "$DECISIONS_DIR" || "$waiver_base" != decision-*.md || "$waiver_base" == "decision-template.md" || "$waiver_base" == "decision-index.md" ]]; then
    fail "external review await gate waiver ref does not resolve to an existing decision record under docs/decisions: ${waiver_ref}"
    return
  fi
  waiver_dir_physical="$(cd "$(dirname "$waiver_path")" && pwd -P)"
  decisions_dir_physical="$(cd "$DECISIONS_DIR" && pwd -P)"
  if [[ "$waiver_dir_physical" != "$decisions_dir_physical" ]]; then
    fail "external review await gate waiver ref does not resolve to an existing decision record under docs/decisions: ${waiver_ref}"
    return
  fi

  decision_status="$(extract_field_value "$waiver_path" "status")"
  decision_chosen_by="$(printf '%s' "$(extract_field_value "$waiver_path" "chosen_by")" | tr '[:upper:]' '[:lower:]')"
  decision_linked_task="$(extract_field_value "$waiver_path" "linked_task")"
  if [[ "$decision_status" != "accepted" ]]; then
    problems="${problems}status must be accepted (got '${decision_status:-missing}'); "
  fi
  if [[ "$decision_chosen_by" != "user" ]]; then
    problems="${problems}chosen_by must be user (got '${decision_chosen_by:-missing}'); "
  fi
  if [[ "$decision_linked_task" != "TASK-${task_id}" ]]; then
    problems="${problems}linked_task must be TASK-${task_id} (got '${decision_linked_task:-missing}'); "
  fi
  if [[ -n "$problems" ]]; then
    fail "external review await gate waiver decision ${waiver_ref} is not a valid user waiver: ${problems%; }"
    return
  fi

  pass "external review await gate waived with a verified user decision"
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

  # Which tasks are evaluated, and how hard (references/orchestration-review-contract.md):
  #   in_progress  advisory AND strict; full evidence verification
  #   done         advisory only; verdict-level reading -- a closed task's evidence is
  #                immutable history and is not re-measured against later rules (same
  #                precedent as the orchestration size cap), and strict never judged it
  #   anything else only when the fail-closed gate asks about this very task
  #                (AWAIT_GATE_TRANSITION=true), i.e. an implementation-start transition
  AWAIT_GATE_VERIFY_TIER="full"
  if [[ "${AWAIT_GATE_TRANSITION:-false}" != "true" ]]; then
    case "$task_status" in
      in_progress) ;;
      done)
        [[ "$MODE" == "advisory" ]] || return 0
        AWAIT_GATE_VERIFY_TIER="verdict"
        ;;
      *) return 0 ;;
    esac
  fi

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
      check_waived_external_review_await_gate "$orchestration_file" "$task_id"
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

# One task for the fail-closed gate. $2 is "true" when the caller named this task, which
# makes the gate answer for it whatever its stored status is (the implementation-start
# transition is requested BEFORE the status moves); a task that is already closed has no
# transition left to guard.
external_review_gate_one_task() {
  local task_id="$1"
  local explicit="$2"
  local task_ref="TASK-${task_id}"
  local task_file="$TASK_DIR/${task_ref}.md"
  local orchestration_file
  local required_for
  local task_status
  local task_status_primary

  orchestration_file="$(codeguide_orchestration_file "$PROJECT_ROOT_ABS" "$task_id")"
  if [[ ! -f "$orchestration_file" ]]; then
    pass "external review gate not required for ${task_ref}: no orchestration capsule"
    return
  fi
  required_for="$(extract_field_value "$orchestration_file" "external_review_required_for")"
  if [[ "$required_for" != "implementation_start" ]]; then
    pass "external review gate not required for ${task_ref}: ORCH external_review_required_for is not implementation_start"
    return
  fi
  if [[ ! -f "$task_file" ]]; then
    fail "external review await gate requires the task file for ${task_ref}: ${task_file}"
    return
  fi

  task_status="$(extract_field_value "$task_file" "status")"
  task_status_primary="${task_status%% *}"
  # A closed task has no transition left to guard -- unless the caller is reopening it
  # (--to-status names a different status), which starts implementation again and is gated
  # like any other start. Without --to-status the caller made no transition claim, so a
  # closed task is not re-measured (re-syncing a historical task must keep working).
  case "$task_status_primary" in
    done|superseded|cancelled)
      if [[ -z "${GATE_TO_STATUS:-}" || "$GATE_TO_STATUS" == "$task_status_primary" ]]; then
        pass "external review gate not required for ${task_ref}: task is already ${task_status_primary}"
        return
      fi
      ;;
  esac

  AWAIT_GATE_TRANSITION="$explicit"
  check_external_review_await_gate_for_task "$task_id" "$task_ref" "$task_file" "$task_status_primary"
  AWAIT_GATE_TRANSITION="false"
}

# validate_docs.sh --gate external-review [--task-id <id>]: the fail-closed counterpart of
# the advisory/strict document checks. It evaluates ONLY the external-review await gate, so
# unrelated advisory noise can neither fail it nor hide in it, and its exit code is the
# verdict: 0 = not required or satisfied, 1 = required and not satisfied (or unverifiable).
# MODE is forced to strict so every violation prints as [FAIL]; with --task-id the gate
# answers for that task regardless of its stored status, without it for every in_progress
# task. Document-check semantics of --mode advisory/strict are untouched.
run_external_review_gate_phase() {
  local gate_task_id="$1"
  local task_file
  local task_id
  local task_status
  local task_status_primary

  MODE="strict"
  AWAIT_GATE_TRANSITION="false"
  if [[ -n "$gate_task_id" ]]; then
    external_review_gate_one_task "$gate_task_id" "true"
  else
    while IFS= read -r task_file; do
      task_id="$(basename "$task_file" .md)"
      task_id="${task_id#TASK-}"
      task_status="$(extract_field_value "$task_file" "status")"
      task_status_primary="${task_status%% *}"
      [[ "$task_status_primary" == "in_progress" ]] || continue
      external_review_gate_one_task "$task_id" "false"
    done < <(find "$TASK_DIR" -maxdepth 1 -type f -name 'TASK-*.md' | sort)
  fi

  if [[ "$VALIDATE_FORMAT" == "json" ]]; then
    emit_json_result
    if (( ISSUE_COUNT > 0 )); then
      exit 1
    fi
    exit 0
  fi
  if (( ISSUE_COUNT > 0 )); then
    echo "[RESULT] External review gate failed with ${ISSUE_COUNT} issue(s)." >&2
    exit 1
  fi
  echo "[RESULT] External review gate passed."
  exit 0
}
