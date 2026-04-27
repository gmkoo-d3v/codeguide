#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_external_plan_reviews.sh <project-root> [options]

Options:
  --task-id <id>                    Task ID for PLAN-<task-id>-<plan-version>.md
  --plan-version <vX.Y>             Plan version to review (required)
  --primary-tool <tool>             Plan author tool: gemini|claude|codex (required)
  --review-round <rNN>              Review round label, e.g. r01 (required)
  --adversarial-evaluator <tool>    Optional reviewer to run in adversarial mode
  --gemini-model <model>            Optional Gemini model override
  --claude-model <model>            Optional Claude model override
  --codex-model <model>             Optional Codex model override
  -h, --help                        Show this message

Environment overrides:
  CODEGUIDE_GEMINI_BIN              Gemini CLI binary path (default: gemini)
  CODEGUIDE_CLAUDE_BIN              Claude CLI binary path (default: claude)
  CODEGUIDE_CODEX_BIN               Codex CLI binary path (default: codex)
  CODEGUIDE_GEMINI_MODEL            Default Gemini model override
  CODEGUIDE_CLAUDE_MODEL            Default Claude model override
  CODEGUIDE_CODEX_MODEL             Default Codex model override
EOF
}

PROJECT_ROOT="."
if [[ $# -gt 0 && "${1:-}" != -* ]]; then
  PROJECT_ROOT="${1%/}"
  shift
fi

TASK_ID=""
PLAN_VERSION=""
PRIMARY_TOOL=""
REVIEW_ROUND=""
ADVERSARIAL_EVALUATOR=""
GEMINI_MODEL="${CODEGUIDE_GEMINI_MODEL:-}"
CLAUDE_MODEL="${CODEGUIDE_CLAUDE_MODEL:-}"
CODEX_MODEL="${CODEGUIDE_CODEX_MODEL:-}"

GEMINI_BIN="${CODEGUIDE_GEMINI_BIN:-gemini}"
CLAUDE_BIN="${CODEGUIDE_CLAUDE_BIN:-claude}"
CODEX_BIN="${CODEGUIDE_CODEX_BIN:-codex}"

TMP_FILES=()

register_tmp_file() {
  TMP_FILES+=("$1")
}

cleanup_tmp_files() {
  local file_path
  for file_path in "${TMP_FILES[@]:-}"; do
    rm -f "$file_path" 2>/dev/null || true
  done
}

trap cleanup_tmp_files EXIT

require_option_value() {
  local option_name="$1"
  local remaining_args="$2"
  if (( remaining_args < 2 )); then
    echo "[ERROR] Option ${option_name} requires a value" >&2
    usage
    exit 1
  fi
}

validate_identifier() {
  local option_name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "[ERROR] Invalid ${option_name}: ${value} (allowed: letters, digits, dot, underscore, hyphen)" >&2
    exit 1
  fi
}

validate_tool() {
  local option_name="$1"
  local value="$2"
  case "$value" in
    gemini|claude|codex) ;;
    *)
      echo "[ERROR] Invalid ${option_name}: ${value} (use gemini, claude, or codex)" >&2
      exit 1
      ;;
  esac
}

validate_plan_version() {
  local value="$1"
  if [[ ! "$value" =~ ^v[0-9]+\.[0-9]+$ ]]; then
    echo "[ERROR] Invalid --plan-version: ${value} (expected v<major>.<minor>)" >&2
    exit 1
  fi
}

validate_review_round() {
  local value="$1"
  if [[ ! "$value" =~ ^r[0-9]{2}$ ]]; then
    echo "[ERROR] Invalid --review-round: ${value} (expected rNN)" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id)
      require_option_value "$1" "$#"
      TASK_ID="${2:-}"
      shift 2
      ;;
    --plan-version)
      require_option_value "$1" "$#"
      PLAN_VERSION="${2:-}"
      shift 2
      ;;
    --primary-tool)
      require_option_value "$1" "$#"
      PRIMARY_TOOL="${2:-}"
      shift 2
      ;;
    --review-round)
      require_option_value "$1" "$#"
      REVIEW_ROUND="${2:-}"
      shift 2
      ;;
    --adversarial-evaluator)
      require_option_value "$1" "$#"
      ADVERSARIAL_EVALUATOR="${2:-}"
      shift 2
      ;;
    --gemini-model)
      require_option_value "$1" "$#"
      GEMINI_MODEL="${2:-}"
      shift 2
      ;;
    --claude-model)
      require_option_value "$1" "$#"
      CLAUDE_MODEL="${2:-}"
      shift 2
      ;;
    --codex-model)
      require_option_value "$1" "$#"
      CODEX_MODEL="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -d "$PROJECT_ROOT" ]]; then
  echo "[ERROR] Project root does not exist: $PROJECT_ROOT" >&2
  exit 1
fi

if [[ -z "$TASK_ID" || -z "$PLAN_VERSION" || -z "$PRIMARY_TOOL" || -z "$REVIEW_ROUND" ]]; then
  echo "[ERROR] --task-id, --plan-version, --primary-tool, and --review-round are required" >&2
  usage
  exit 1
fi

validate_identifier "--task-id" "$TASK_ID"
validate_plan_version "$PLAN_VERSION"
validate_tool "--primary-tool" "$PRIMARY_TOOL"
validate_review_round "$REVIEW_ROUND"
if [[ -n "$ADVERSARIAL_EVALUATOR" ]]; then
  validate_tool "--adversarial-evaluator" "$ADVERSARIAL_EVALUATOR"
fi

INPUT_ROOT_ABS="$(cd "$PROJECT_ROOT" && pwd)"
resolve_repo_root() {
  git -C "$INPUT_ROOT_ABS" rev-parse --show-toplevel 2>/dev/null || printf "%s" "$INPUT_ROOT_ABS"
}

PROJECT_ROOT_ABS="$(resolve_repo_root)"
WORKSPACE_ROOT="$(cd "$PROJECT_ROOT_ABS/.." && pwd)"
DOCS_DIR="$WORKSPACE_ROOT/docs"
TASK_DIR="$DOCS_DIR/task"
DECISIONS_DIR="$DOCS_DIR/decisions"
PLAN_DIR="$DOCS_DIR/plan"
REPORT_DIR="$DOCS_DIR/report"
ORCHESTRATION_DIR="$DOCS_DIR/orchestration"
HANDOFF_DIR="$ORCHESTRATION_DIR/external-cli/$TASK_ID/$PLAN_VERSION/$REVIEW_ROUND"

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_SCRIPT="$THIS_DIR/init_docs_scaffold.sh"
PROMPT_TEMPLATE_FILE="$THIS_DIR/../references/external-plan-review-prompt.md"

"$INIT_SCRIPT" "$PROJECT_ROOT_ABS"
mkdir -p "$HANDOFF_DIR"

PLAN_FILE="$PLAN_DIR/PLAN-${TASK_ID}-${PLAN_VERSION}.md"
if [[ ! -f "$PLAN_FILE" ]]; then
  echo "[ERROR] Plan file not found: $PLAN_FILE" >&2
  exit 1
fi

if [[ ! -f "$PROMPT_TEMPLATE_FILE" ]]; then
  echo "[ERROR] Prompt template not found: $PROMPT_TEMPLATE_FILE" >&2
  exit 1
fi

normalize_one_line() {
  printf "%s" "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//'
}

escape_sed() {
  printf "%s" "$1" | sed 's/[\\&|]/\\&/g'
}

extract_field_value() {
  local file_path="$1"
  local key="$2"
  local raw
  raw="$(grep -E "^- ${key}:" "$file_path" 2>/dev/null | head -n 1 | sed "s/^- ${key}:[[:space:]]*//" || true)"
  normalize_one_line "$raw"
}

ensure_plan_field() {
  local key="$1"
  local value
  value="$(extract_field_value "$PLAN_FILE" "$key")"
  if [[ -z "$value" ]]; then
    echo "[ERROR] Plan field '${key}' must be non-empty before external review: $PLAN_FILE" >&2
    exit 1
  fi
}

ensure_plan_field "task_id"
ensure_plan_field "plan_version"
ensure_plan_field "objective"
ensure_plan_field "scope"

PLAN_TASK_ID="$(extract_field_value "$PLAN_FILE" "task_id")"
PLAN_DOC_VERSION="$(extract_field_value "$PLAN_FILE" "plan_version")"
if [[ "$PLAN_TASK_ID" != "$TASK_ID" ]]; then
  echo "[ERROR] task_id mismatch between file and option: ${PLAN_TASK_ID} != ${TASK_ID}" >&2
  exit 1
fi
if [[ "$PLAN_DOC_VERSION" != "$PLAN_VERSION" ]]; then
  echo "[ERROR] plan_version mismatch between file and option: ${PLAN_DOC_VERSION} != ${PLAN_VERSION}" >&2
  exit 1
fi

ensure_orchestration_file() {
  local orchestration_file="$1"
  local template_file="$ORCHESTRATION_DIR/ORCH-template.md"

  if [[ -f "$orchestration_file" ]]; then
    return
  fi

  if [[ -f "$template_file" ]]; then
    cp "$template_file" "$orchestration_file"
    sed -i.bak "1s|^# ORCH-<task-id>$|# ORCH-${TASK_ID}|" "$orchestration_file"
    rm -f "${orchestration_file}.bak"
    return
  fi

  cat > "$orchestration_file" <<EOF
# ORCH-${TASK_ID}

- task_id:
- execution_mode: supervisor_subagents | solo
- primary_author_tool: gemini | claude | codex
- review_mode: external_cli | codex_subagents
- supervisor_agent:
- planner_agents:
- reviewer_agents:
- implementation_agents:
- validation_agents:
- owned_scopes:
- delegation_status: planned | active | completed | blocked
- delegation_note:
- last_updated:
EOF
}

upsert_field() {
  local file_path="$1"
  local key="$2"
  local value="$3"
  local normalized
  local escaped

  normalized="$(normalize_one_line "$value")"
  escaped="$(escape_sed "$normalized")"

  if grep -qE "^- ${key}:" "$file_path" 2>/dev/null; then
    sed -i.bak "s|^- ${key}:.*|- ${key}: ${escaped}|" "$file_path"
    rm -f "${file_path}.bak"
  else
    printf -- "- %s: %s\n" "$key" "$normalized" >> "$file_path"
  fi
}

upsert_field_if_blank() {
  local file_path="$1"
  local key="$2"
  local value="$3"
  local current_value

  current_value="$(extract_field_value "$file_path" "$key")"
  if [[ -n "$current_value" ]]; then
    return
  fi
  upsert_field "$file_path" "$key" "$value"
}

normalize_risk_level_value() {
  printf "%s" "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g'
}

risk_level_requires_adversarial() {
  local risk_level="$1"
  [[ "$risk_level" == "high" || "$risk_level" == "critical" ]]
}

high_risk_source_for_task() {
  local task_file="$TASK_DIR/TASK-${TASK_ID}.md"
  local task_risk_level=""
  local decision_file
  local linked_task
  local decision_status
  local decision_risk_level

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
    [[ "$linked_task" == "TASK-${TASK_ID}" ]] || continue

    decision_status="$(extract_field_value "$decision_file" "status")"
    [[ "$decision_status" == "superseded" ]] && continue

    decision_risk_level="$(normalize_risk_level_value "$(extract_field_value "$decision_file" "risk_level")")"
    if risk_level_requires_adversarial "$decision_risk_level"; then
      printf "%s risk_level=%s" "$(basename "$decision_file")" "$decision_risk_level"
      return
    fi
  done < <(find "$DECISIONS_DIR" -maxdepth 1 -type f -name 'decision-*.md' ! -name 'decision-template.md' ! -name 'decision-index.md' | sort)
}

ORCHESTRATION_FILE="$ORCHESTRATION_DIR/ORCH-${TASK_ID}.md"
ensure_orchestration_file "$ORCHESTRATION_FILE"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
upsert_field "$ORCHESTRATION_FILE" "task_id" "$TASK_ID"
upsert_field_if_blank "$ORCHESTRATION_FILE" "execution_mode" "supervisor_subagents"
upsert_field "$ORCHESTRATION_FILE" "primary_author_tool" "$PRIMARY_TOOL"
upsert_field "$ORCHESTRATION_FILE" "review_mode" "external_cli"
upsert_field_if_blank "$ORCHESTRATION_FILE" "supervisor_agent" "external-review-wrapper"
upsert_field "$ORCHESTRATION_FILE" "last_updated" "$NOW_UTC"

ALL_TOOLS=(gemini claude codex)
REVIEWERS=()
for tool in "${ALL_TOOLS[@]}"; do
  if [[ "$tool" != "$PRIMARY_TOOL" ]]; then
    REVIEWERS+=("$tool")
  fi
done

upsert_field_if_blank "$ORCHESTRATION_FILE" "planner_agents" "${PRIMARY_TOOL}-primary-author"
upsert_field "$ORCHESTRATION_FILE" "reviewer_agents" "$(IFS=,; printf "external-cli:%s" "${REVIEWERS[*]}")"
upsert_field_if_blank "$ORCHESTRATION_FILE" "implementation_agents" "pending-implementation-selection"
upsert_field_if_blank "$ORCHESTRATION_FILE" "validation_agents" "pending-validation-selection"
upsert_field_if_blank "$ORCHESTRATION_FILE" "owned_scopes" "planner: docs/plan; reviewers: docs/report; implementation: pending; validation: pending"
upsert_field_if_blank "$ORCHESTRATION_FILE" "delegation_status" "active"

HIGH_RISK_SOURCE="$(high_risk_source_for_task || true)"
if [[ -n "$HIGH_RISK_SOURCE" && -z "$ADVERSARIAL_EVALUATOR" ]]; then
  ADVERSARIAL_EVALUATOR="${REVIEWERS[0]}"
  echo "[INFO] High-risk task detected (${HIGH_RISK_SOURCE}); auto-selecting adversarial evaluator=${ADVERSARIAL_EVALUATOR}"
fi

if [[ -n "$ADVERSARIAL_EVALUATOR" ]]; then
  found="false"
  for tool in "${REVIEWERS[@]}"; do
    if [[ "$tool" == "$ADVERSARIAL_EVALUATOR" ]]; then
      found="true"
      break
    fi
  done
  if [[ "$found" != "true" ]]; then
    echo "[ERROR] adversarial evaluator must be one of the non-primary reviewers: ${REVIEWERS[*]}" >&2
    exit 1
  fi
fi

PROMPT_TEMPLATE="$(cat "$PROMPT_TEMPLATE_FILE")"

build_prompt() {
  local evaluator="$1"
  local review_style="$2"
  local strict_retry="${3:-false}"
  local retry_note=""

  if [[ "$strict_retry" == "true" ]]; then
    retry_note=$'\nFormatting retry:\n- Your previous response was unusable because required fields were missing or malformed.\n- Return only the exact bullet fields requested below.\n- Keep every field value on one line.\n'
  fi

  cat <<EOF
${PROMPT_TEMPLATE}

Review metadata:
- task_id: ${TASK_ID}
- plan_version: ${PLAN_VERSION}
- evaluator: ${evaluator}
- review_style: ${review_style}
- review_round: ${REVIEW_ROUND}
- primary_author_tool: ${PRIMARY_TOOL}

Output contract:
- Return only markdown bullet lines.
- Keep every field value on one line.
- Use concrete, evidence-based criticism.
- Default stance is defect-seeking, not approval-seeking.
- Prefer contract mismatches, weak assumptions, missing verification, sequencing flaws, convention drift, and understated risks over praise.
- Valid verdict values: accept | revise | blocked
- If the plan is not execution-ready, prefer revise or blocked.
${retry_note}
Return exactly these fields:
- verdict:
- summary:
- strengths:
- risks:
- requested_changes:
EOF

  if [[ "$review_style" == "adversarial" ]]; then
    cat <<'EOF'
- objection:
- counterproposal:
- rebuttal:
- residual_risk:
EOF
  fi
}

write_handoff_request() {
  local request_file="$1"
  local response_file="$2"
  local evaluator="$3"
  local review_style="$4"
  local strict_retry="${5:-false}"

  cat > "$request_file" <<EOF
# External plan review request (${evaluator})

- task_id: ${TASK_ID}
- plan_version: ${PLAN_VERSION}
- evaluator: ${evaluator}
- review_style: ${review_style}
- review_round: ${REVIEW_ROUND}
- primary_author_tool: ${PRIMARY_TOOL}
- source_plan_file: ${PLAN_FILE}
- expected_response_file: ${response_file}

## Why

- Collect an evidence-based external review without passing a long prompt through shell arguments.
- Preserve the raw request and response as Markdown orchestration artifacts.

## What

- Review PLAN-${TASK_ID}-${PLAN_VERSION} as ${evaluator} in ${review_style} mode for round ${REVIEW_ROUND}.
- Return only the parser-compatible Markdown bullet fields requested in the instructions.

## How

- Use the output contract above exactly.
- Keep every field value on one line so the wrapper can normalize the response into docs/report/.
- Prefer concrete defects, missing safeguards, and verification gaps over approval-oriented feedback.

### Detailed Instructions

$(build_prompt "$evaluator" "$review_style" "$strict_retry")

## Where

- Source plan file: ${PLAN_FILE}
- Raw response file expected by wrapper: ${response_file}
- Final normalized report directory: ${REPORT_DIR}

## Verify

- Valid verdict values are accept, revise, or blocked.
- Standard reviews must include verdict, summary, strengths, risks, and requested_changes.
- Adversarial reviews must also include objection, counterproposal, rebuttal, and residual_risk.

## Payload

### Plan under review

\`\`\`markdown
$(cat "$PLAN_FILE")
\`\`\`
EOF
}

tool_model_for() {
  local tool="$1"
  case "$tool" in
    gemini) printf "%s" "$GEMINI_MODEL" ;;
    claude) printf "%s" "$CLAUDE_MODEL" ;;
    codex) printf "%s" "$CODEX_MODEL" ;;
  esac
}

tool_bin_for() {
  local tool="$1"
  case "$tool" in
    gemini) printf "%s" "$GEMINI_BIN" ;;
    claude) printf "%s" "$CLAUDE_BIN" ;;
    codex) printf "%s" "$CODEX_BIN" ;;
  esac
}

run_tool_prompt() {
  local tool="$1"
  local request_file="$2"
  local response_file="$3"
  local stderr_file="$4"
  local model_override
  local binary
  local prompt
  local -a cmd

  binary="$(tool_bin_for "$tool")"
  model_override="$(tool_model_for "$tool")"
  prompt="Read the Markdown request file at ${request_file}, review the embedded plan, and return only the requested markdown bullet fields. The wrapper will save stdout to ${response_file}."

  if ! command -v "$binary" >/dev/null 2>&1; then
    echo "[ERROR] ${tool} binary not found in PATH: ${binary}" > "$stderr_file"
    return 127
  fi

  case "$tool" in
    gemini)
      cmd=("$binary" --approval-mode plan --output-format text)
      if [[ -n "$model_override" ]]; then
        cmd+=(-m "$model_override")
      fi
      cmd+=(-p "$prompt")
      ;;
    claude)
      cmd=("$binary" -p --permission-mode plan --output-format text)
      if [[ -n "$model_override" ]]; then
        cmd+=(--model "$model_override")
      fi
      cmd+=("$prompt")
      ;;
    codex)
      cmd=("$binary" exec --skip-git-repo-check --sandbox read-only -C "$PROJECT_ROOT_ABS")
      if [[ -n "$model_override" ]]; then
        cmd+=(-m "$model_override")
      fi
      cmd+=("$prompt")
      ;;
  esac

  if "${cmd[@]}" <"$request_file" >"$response_file" 2>"$stderr_file"; then
    return 0
  fi
  return $?
}

preserve_stderr_if_needed() {
  local temp_stderr_file="$1"
  local durable_stderr_file="$2"
  local status="$3"

  if [[ "$status" -ne 0 || -s "$temp_stderr_file" ]]; then
    cp "$temp_stderr_file" "$durable_stderr_file"
  else
    rm -f "$durable_stderr_file" 2>/dev/null || true
  fi
}

PARSED_VERDICT=""
PARSED_SUMMARY=""
PARSED_STRENGTHS=""
PARSED_RISKS=""
PARSED_REQUESTED_CHANGES=""
PARSED_OBJECTION=""
PARSED_COUNTERPROPOSAL=""
PARSED_REBUTTAL=""
PARSED_RESIDUAL_RISK=""

parse_review_response() {
  local response_file="$1"
  local review_style="$2"

  PARSED_VERDICT="$(extract_field_value "$response_file" "verdict" | tr '[:upper:]' '[:lower:]')"
  PARSED_SUMMARY="$(extract_field_value "$response_file" "summary")"
  PARSED_STRENGTHS="$(extract_field_value "$response_file" "strengths")"
  PARSED_RISKS="$(extract_field_value "$response_file" "risks")"
  PARSED_REQUESTED_CHANGES="$(extract_field_value "$response_file" "requested_changes")"
  PARSED_OBJECTION="$(extract_field_value "$response_file" "objection")"
  PARSED_COUNTERPROPOSAL="$(extract_field_value "$response_file" "counterproposal")"
  PARSED_REBUTTAL="$(extract_field_value "$response_file" "rebuttal")"
  PARSED_RESIDUAL_RISK="$(extract_field_value "$response_file" "residual_risk")"

  if [[ ! "$PARSED_VERDICT" =~ ^(accept|revise|blocked)$ ]]; then
    return 1
  fi
  if [[ -z "$PARSED_SUMMARY" || -z "$PARSED_STRENGTHS" || -z "$PARSED_RISKS" || -z "$PARSED_REQUESTED_CHANGES" ]]; then
    return 1
  fi
  if [[ "$review_style" == "adversarial" ]]; then
    if [[ -z "$PARSED_OBJECTION" || -z "$PARSED_COUNTERPROPOSAL" || -z "$PARSED_REBUTTAL" || -z "$PARSED_RESIDUAL_RISK" ]]; then
      return 1
    fi
  fi
  return 0
}

write_report_file() {
  local evaluator="$1"
  local review_style="$2"
  local report_file="$3"
  local now_utc

  now_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  cat > "$report_file" <<EOF
# PLAN-${TASK_ID}-${PLAN_VERSION} review (${evaluator})

- task_id: ${TASK_ID}
- plan_version: ${PLAN_VERSION}
- evaluator: ${evaluator}
- review_style: ${review_style}
- review_round: ${REVIEW_ROUND}
- verdict: ${PARSED_VERDICT}
- summary: ${PARSED_SUMMARY}
- strengths: ${PARSED_STRENGTHS}
- risks: ${PARSED_RISKS}
- requested_changes: ${PARSED_REQUESTED_CHANGES}
- objection: ${PARSED_OBJECTION}
- counterproposal: ${PARSED_COUNTERPROPOSAL}
- rebuttal: ${PARSED_REBUTTAL}
- residual_risk: ${PARSED_RESIDUAL_RISK}
- last_updated: ${now_utc}
EOF
}

SUCCESS_COUNT=0
FAIL_COUNT=0
STATUS_LINES=()
ADVERSARIAL_SUCCESS="false"

for reviewer in "${REVIEWERS[@]}"; do
  review_style="standard"
  if [[ -n "$ADVERSARIAL_EVALUATOR" && "$reviewer" == "$ADVERSARIAL_EVALUATOR" ]]; then
    review_style="adversarial"
  fi

  report_file="$REPORT_DIR/PLAN-${TASK_ID}-${PLAN_VERSION}-review-${reviewer}-${REVIEW_ROUND}.md"
  if [[ -f "$report_file" ]]; then
    stale_file="${report_file}.stale-${NOW_UTC}"
    mv "$report_file" "$stale_file"
  fi

  request_file="$HANDOFF_DIR/${reviewer}.request.md"
  response_file="$HANDOFF_DIR/${reviewer}.response.md"
  stderr_durable_file="$HANDOFF_DIR/${reviewer}.stderr.md"
  stderr_file="$(mktemp)"
  register_tmp_file "$stderr_file"

  rm -f "$request_file" "$response_file" "$stderr_durable_file" \
    "$HANDOFF_DIR/${reviewer}.retry-request.md" \
    "$HANDOFF_DIR/${reviewer}.retry-response.md" \
    "$HANDOFF_DIR/${reviewer}.retry-stderr.md"

  write_handoff_request "$request_file" "$response_file" "$reviewer" "$review_style" "false"
  run_status=0
  if run_tool_prompt "$reviewer" "$request_file" "$response_file" "$stderr_file"; then
    run_status=0
  else
    run_status=$?
  fi
  preserve_stderr_if_needed "$stderr_file" "$stderr_durable_file" "$run_status"

  if [[ "$run_status" -eq 0 ]] && parse_review_response "$response_file" "$review_style"; then
    :
  elif [[ "$run_status" -eq 0 ]]; then
    retry_request_file="$HANDOFF_DIR/${reviewer}.retry-request.md"
    retry_response_file="$HANDOFF_DIR/${reviewer}.retry-response.md"
    retry_stderr_durable_file="$HANDOFF_DIR/${reviewer}.retry-stderr.md"
    retry_stderr="$(mktemp)"
    register_tmp_file "$retry_stderr"
    write_handoff_request "$retry_request_file" "$retry_response_file" "$reviewer" "$review_style" "true"
    retry_status=0
    if run_tool_prompt "$reviewer" "$retry_request_file" "$retry_response_file" "$retry_stderr"; then
      retry_status=0
    else
      retry_status=$?
    fi
    preserve_stderr_if_needed "$retry_stderr" "$retry_stderr_durable_file" "$retry_status"

    if [[ "$retry_status" -eq 0 ]] && parse_review_response "$retry_response_file" "$review_style"; then
      response_file="$retry_response_file"
      stderr_file="$retry_stderr"
      run_status=0
    else
      run_status=65
      if [[ "$retry_status" -ne 0 ]]; then
        stderr_file="$retry_stderr"
      fi
    fi
  fi

  if [[ "$run_status" -eq 0 ]]; then
    write_report_file "$reviewer" "$review_style" "$report_file"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    if [[ "$review_style" == "adversarial" ]]; then
      ADVERSARIAL_SUCCESS="true"
    fi
    STATUS_LINES+=("[OK] evaluator=${reviewer} style=${review_style} verdict=${PARSED_VERDICT} file=${report_file} summary=$(normalize_one_line "$PARSED_SUMMARY")")
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    failure_reason="$(normalize_one_line "$(cat "$stderr_file" 2>/dev/null || true)")"
    if [[ -z "$failure_reason" ]]; then
      failure_reason="response missing required fields"
    fi
    STATUS_LINES+=("[FAIL] evaluator=${reviewer} style=${review_style} reason=${failure_reason}")
  fi
done

printf "%s\n" "${STATUS_LINES[@]}"
echo "[INFO] review_successes=${SUCCESS_COUNT} review_failures=${FAIL_COUNT}"
echo "[INFO] Semi-automated stop reached. No new plan version was created automatically."

if [[ -n "$ADVERSARIAL_EVALUATOR" && "$ADVERSARIAL_SUCCESS" != "true" ]]; then
  echo "[ERROR] Required adversarial review did not complete successfully for evaluator=${ADVERSARIAL_EVALUATOR}" >&2
  exit 1
fi

if [[ "$SUCCESS_COUNT" -gt 0 ]]; then
  exit 0
fi

exit 1
