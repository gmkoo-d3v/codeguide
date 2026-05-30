#!/usr/bin/env bash

set -euo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_REGISTRY_FILE="${CODEGUIDE_MODEL_REGISTRY:-$THIS_DIR/../config/ai_model_registry.json}"

usage() {
  cat <<'EOF'
Usage:
  run_external_plan_reviews.sh <project-root> [options]

Options:
  --task-id <id>                    Task ID for PLAN-<task-id>-<plan-version>.md
  --plan-version <vX.Y>             Plan version to review (required)
  --primary-tool <tool>             Plan author/coordinator tool: antigravity|agy|claude|codex|human|external-runner (required)
  --review-round <rNN>              Review round label, e.g. r01 (required)
  --risk-preflight-status <status>  Required gate before external review: approved (pass is rejected for external CLI)
  --risk-preflight-recorded-by <id> Main-thread actor that performed preflight (default: main-thread-supervising-lead-architect)
  --risk-preflight-summary "<text>" Required gate summary (default: external review cleared by main thread)
  --approval-ref <ref>              Required when risk-preflight-status=approved
  --approved-next-step "<text>"     Exact approved step when approval was required
  --reviewer <model>                Optional reviewer model alias to invoke; repeatable, default is all non-primary models
  --adversarial-evaluator <model>   Optional reviewer model to run in adversarial mode
  --allow-partial-review            Allow success when only one non-required reviewer succeeds
  --manual-handoff-only             Write request files and manual command files, then stop without invoking external CLIs
  --ingest-manual-responses         Parse existing manual raw/response files into reports and provenance without invoking external CLIs
  --primary-model <model>           Override the primary model alias used to exclude self-review
  --antigravity-model <model>       Backward-compatible alias for --primary-model
  --task-phase <phase>              Task phase: planning|review|code|implementation (registry default when unset)
  -h, --help                        Show this message

Environment overrides:
  CODEGUIDE_ANTIGRAVITY_BIN         agy CLI binary path (default from registry: agy)
  CODEGUIDE_CLAUDE_BIN              Claude Code CLI binary path (default: claude)
  CODEGUIDE_CODEX_BIN               Codex CLI binary path (default: codex)
  CODEGUIDE_PRIMARY_MODEL           Default primary model alias (registry default when unset)
  CODEGUIDE_ANTIGRAVITY_MODEL       Backward-compatible alias for CODEGUIDE_PRIMARY_MODEL
  CODEGUIDE_MODEL_REGISTRY          Model registry JSON path
  CODEGUIDE_TASK_PHASE              Default task phase (registry default when unset)

Model Registry:
  Runners, model routes, aliases, quota groups, default reviewers, quota patterns,
  and quota-stop policy are read from CODEGUIDE_MODEL_REGISTRY, or from the bundled
  registry next to this script.

Quota Exhaustion Policy:
  If a registered model route quota is exhausted, the wrapper stops and asks the
  user to switch the runner's globally selected model, then rerun with the route
  that records the new selection. The wrapper does not auto-edit runner settings.
EOF
}

PROJECT_ROOT="."
if [[ $# -gt 0 && "${1:-}" != -* ]]; then
  PROJECT_ROOT="${1%/}"
  shift
fi

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
done

TASK_ID=""
PLAN_VERSION=""
PRIMARY_TOOL=""
REVIEW_ROUND=""
RISK_PREFLIGHT_STATUS=""
RISK_PREFLIGHT_RECORDED_BY="main-thread-supervising-lead-architect"
RISK_PREFLIGHT_SUMMARY=""
APPROVAL_REF=""
APPROVED_NEXT_STEP=""
ADVERSARIAL_EVALUATOR=""
ALLOW_PARTIAL_REVIEW="false"
MANUAL_HANDOFF_ONLY="false"
INGEST_MANUAL_RESPONSES="false"
SELECTED_REVIEWERS=()

# Runner-aware model registry. Values are loaded from JSON below.
DEFAULT_MODEL_ALIAS=""
DEFAULT_TASK_PHASE="planning"
MODEL_ALIAS_KEYS=()
MODEL_ALIAS_VALUES=()
RUNNER_IDS=()
RUNNER_BINARIES=()
RUNNER_ENV_BINARIES=()
RUNNER_COMMAND_KINDS=()
MODEL_ROUTE_IDS=()
MODEL_RUNNERS=()
MODEL_CLI_MODELS=()
MODEL_QUOTA_GROUPS=()
MODEL_DISPLAY_NAMES=()
FALLBACK_FROM_GROUPS=()
FALLBACK_PHASES=()
FALLBACK_TARGETS=()
DEFAULT_REVIEWER_ALIASES=()
QUOTA_ERROR_PATTERNS=()
PRIMARY_MODEL=""
TASK_PHASE=""


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
    antigravity|agy|claude|codex|human|external-runner) ;;
    *)
      echo "[ERROR] Invalid ${option_name}: ${value} (use antigravity, agy, claude, codex, human, or external-runner)" >&2
      exit 1
      ;;
  esac
}

load_model_registry() {
  local registry_file="$1"
  local registry_output
  local kind first second third fourth fifth

  if [[ ! -f "$registry_file" ]]; then
    echo "[ERROR] Model registry not found: $registry_file" >&2
    exit 1
  fi

  if ! registry_output="$(python3 "$THIS_DIR/ai_model_registry.py" emit-shell "$registry_file")"; then
    exit 1
  fi

  MODEL_ALIAS_KEYS=()
  MODEL_ALIAS_VALUES=()
  RUNNER_IDS=()
  RUNNER_BINARIES=()
  RUNNER_ENV_BINARIES=()
  RUNNER_COMMAND_KINDS=()
  MODEL_ROUTE_IDS=()
  MODEL_RUNNERS=()
  MODEL_CLI_MODELS=()
  MODEL_QUOTA_GROUPS=()
  MODEL_DISPLAY_NAMES=()
  FALLBACK_FROM_GROUPS=()
  FALLBACK_PHASES=()
  FALLBACK_TARGETS=()
  DEFAULT_REVIEWER_ALIASES=()
  QUOTA_ERROR_PATTERNS=()

  while IFS=$'\t' read -r kind first second third fourth fifth; do
    case "$kind" in
      default_model)
        DEFAULT_MODEL_ALIAS="$first"
        ;;
      default_task_phase)
        DEFAULT_TASK_PHASE="$first"
        ;;
      alias)
        MODEL_ALIAS_KEYS+=("$first")
        MODEL_ALIAS_VALUES+=("$second")
        ;;
      runner)
        RUNNER_IDS+=("$first")
        RUNNER_BINARIES+=("$second")
        RUNNER_ENV_BINARIES+=("$third")
        RUNNER_COMMAND_KINDS+=("$fourth")
        ;;
      model)
        MODEL_ROUTE_IDS+=("$first")
        MODEL_RUNNERS+=("$second")
        MODEL_CLI_MODELS+=("$third")
        MODEL_QUOTA_GROUPS+=("$fourth")
        MODEL_DISPLAY_NAMES+=("$fifth")
        ;;
      fallback)
        FALLBACK_FROM_GROUPS+=("$first")
        FALLBACK_PHASES+=("$second")
        FALLBACK_TARGETS+=("$third")
        ;;
      default_reviewer)
        DEFAULT_REVIEWER_ALIASES+=("$first")
        ;;
      quota_pattern)
        QUOTA_ERROR_PATTERNS+=("$first")
        ;;
      "")
        ;;
      *)
        echo "[ERROR] Unknown model registry record kind: $kind" >&2
        exit 1
        ;;
    esac
  done <<< "$registry_output"

  if [[ -z "$DEFAULT_MODEL_ALIAS" || ${#MODEL_ALIAS_KEYS[@]} -eq 0 || ${#RUNNER_IDS[@]} -eq 0 || ${#MODEL_ROUTE_IDS[@]} -eq 0 || ${#DEFAULT_REVIEWER_ALIASES[@]} -eq 0 || ${#QUOTA_ERROR_PATTERNS[@]} -eq 0 ]]; then
    echo "[ERROR] Model registry is missing one or more required sections: $registry_file" >&2
    exit 1
  fi
}

# Resolve a semantic model alias to a runner-qualified model route.
resolve_model_name() {
  local alias="$1"
  local index
  for (( index=0; index<${#MODEL_ROUTE_IDS[@]}; index++ )); do
    if [[ "${MODEL_ROUTE_IDS[$index]}" == "$alias" ]]; then
      printf "%s" "$alias"
      return
    fi
  done
  for (( index=0; index<${#MODEL_ALIAS_KEYS[@]}; index++ )); do
    if [[ "${MODEL_ALIAS_KEYS[$index]}" == "$alias" ]]; then
      printf "%s" "${MODEL_ALIAS_VALUES[$index]}"
      return
    fi
  done
  printf "%s" "$alias"
}

model_index_for() {
  local route="$1"
  local index
  for (( index=0; index<${#MODEL_ROUTE_IDS[@]}; index++ )); do
    if [[ "${MODEL_ROUTE_IDS[$index]}" == "$route" ]]; then
      printf "%s" "$index"
      return
    fi
  done
  return 1
}

runner_index_for() {
  local runner_id="$1"
  local index
  for (( index=0; index<${#RUNNER_IDS[@]}; index++ )); do
    if [[ "${RUNNER_IDS[$index]}" == "$runner_id" ]]; then
      printf "%s" "$index"
      return
    fi
  done
  return 1
}

quota_group_for_model() {
  local route="$1"
  local index
  if index="$(model_index_for "$route")"; then
    printf "%s" "${MODEL_QUOTA_GROUPS[$index]}"
    return
  fi
  printf "unknown"
}

model_runner_for() {
  local route="$1"
  local index
  if index="$(model_index_for "$route")"; then
    printf "%s" "${MODEL_RUNNERS[$index]}"
    return
  fi
  return 1
}

model_cli_model_for() {
  local route="$1"
  local index
  if index="$(model_index_for "$route")"; then
    printf "%s" "${MODEL_CLI_MODELS[$index]}"
    return
  fi
  return 1
}

model_display_name_for() {
  local route="$1"
  local index
  if index="$(model_index_for "$route")"; then
    printf "%s" "${MODEL_DISPLAY_NAMES[$index]}"
    return
  fi
  return 1
}

runner_binary_for() {
  local runner_id="$1"
  local index
  local env_name
  if index="$(runner_index_for "$runner_id")"; then
    env_name="${RUNNER_ENV_BINARIES[$index]}"
    if [[ -n "$env_name" && -n "${!env_name:-}" ]]; then
      printf "%s" "${!env_name}"
      return
    fi
    printf "%s" "${RUNNER_BINARIES[$index]}"
    return
  fi
  return 1
}

runner_command_kind_for() {
  local runner_id="$1"
  local index
  if index="$(runner_index_for "$runner_id")"; then
    printf "%s" "${RUNNER_COMMAND_KINDS[$index]}"
    return
  fi
  return 1
}

model_selection_for_model() {
  local route="$1"
  require_registered_model "model_selection" "$route" >/dev/null || return 1
  printf "%s" "preconfigured_runtime"
}

primary_model_for_tool() {
  local tool="$1"
  case "$tool" in
    antigravity|agy)
      printf "%s" "agy-current"
      ;;
    claude)
      printf "%s" "claude-current"
      ;;
    codex)
      printf "%s" "codex-current"
      ;;
    *)
      printf "%s" "$DEFAULT_MODEL_ALIAS"
      ;;
  esac
}

quota_exhausted_message() {
  local route="$1"
  local quota_group="$2"
  local runner_id

  runner_id="$(model_runner_for "$route")"
  cat <<EOF
[BLOCKED] Quota exhausted for route '${route}' (quota_group=${quota_group}).
Switch the globally selected model in runner '${runner_id}' to a non-exhausted model, then rerun with a reviewer route that records that selection.
Do not auto-edit runner settings from this wrapper.
EOF
}

# Detect quota/rate-limit exhaustion from a stderr file.
# Returns 0 (true) if a quota pattern is found.
is_quota_exhausted() {
  local stderr_file="$1"
  local pattern
  for pattern in "${QUOTA_ERROR_PATTERNS[@]}"; do
    if grep -Fqi -- "$pattern" "$stderr_file" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

require_registered_model() {
  local context="$1"
  local value="$2"
  local resolved

  resolved="$(resolve_model_name "$value")"
  if ! model_index_for "$resolved" >/dev/null; then
    echo "[ERROR] Model registry reference '${context}' resolves to unregistered model '${resolved}'" >&2
    exit 1
  fi
  printf "%s" "$resolved"
}

validate_model_registry_references() {
  local index

  require_registered_model "default_model_alias" "$DEFAULT_MODEL_ALIAS" >/dev/null

  for (( index=0; index<${#MODEL_ALIAS_VALUES[@]}; index++ )); do
    require_registered_model "aliases[${MODEL_ALIAS_KEYS[$index]}]" "${MODEL_ALIAS_VALUES[$index]}" >/dev/null
  done

  for (( index=0; index<${#DEFAULT_REVIEWER_ALIASES[@]}; index++ )); do
    require_registered_model "default_reviewer_aliases[$index]" "${DEFAULT_REVIEWER_ALIASES[$index]}" >/dev/null
  done

  for (( index=0; index<${#FALLBACK_TARGETS[@]}; index++ )); do
    require_registered_model "fallback_policy.on_quota_exhausted[$index].to" "${FALLBACK_TARGETS[$index]}" >/dev/null
  done
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

validate_risk_preflight_status() {
  local value="$1"
  case "$value" in
    pass|approved|blocked|approval_required) ;;
    *)
      echo "[ERROR] Invalid --risk-preflight-status: ${value} (use pass, approved, blocked, or approval_required)" >&2
      exit 1
      ;;
  esac
}

validate_risk_preflight_recorder() {
  local value="$1"
  local normalized
  if [[ -z "$value" ]]; then
    echo "[ERROR] --risk-preflight-recorded-by must be non-empty" >&2
    exit 1
  fi
  normalized="$(printf "%s" "$value" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$normalized" in
    antigravity|agy|claude|codex|gemini|external-review-wrapper|external-cli*)
      echo "[ERROR] --risk-preflight-recorded-by must identify the main-thread supervising lead architect, not evaluator/tool identity: ${value}" >&2
      exit 1
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

load_model_registry "$MODEL_REGISTRY_FILE"
validate_model_registry_references
PRIMARY_MODEL="${CODEGUIDE_PRIMARY_MODEL:-${CODEGUIDE_ANTIGRAVITY_MODEL:-}}"
PRIMARY_MODEL_EXPLICIT="false"
if [[ -n "$PRIMARY_MODEL" ]]; then
  PRIMARY_MODEL_EXPLICIT="true"
fi
TASK_PHASE="${CODEGUIDE_TASK_PHASE:-$DEFAULT_TASK_PHASE}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id)
      require_option_value "$1" "$#"
      TASK_ID="${2:-}"
      shift 2
      ;;
    --task-phase)
      require_option_value "$1" "$#"
      TASK_PHASE="${2:-}"
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
    --risk-preflight-status)
      require_option_value "$1" "$#"
      RISK_PREFLIGHT_STATUS="${2:-}"
      shift 2
      ;;
    --risk-preflight-recorded-by)
      require_option_value "$1" "$#"
      RISK_PREFLIGHT_RECORDED_BY="${2:-}"
      shift 2
      ;;
    --risk-preflight-summary)
      require_option_value "$1" "$#"
      RISK_PREFLIGHT_SUMMARY="${2:-}"
      shift 2
      ;;
    --approval-ref)
      require_option_value "$1" "$#"
      APPROVAL_REF="${2:-}"
      shift 2
      ;;
    --approved-next-step)
      require_option_value "$1" "$#"
      APPROVED_NEXT_STEP="${2:-}"
      shift 2
      ;;
    --reviewer)
      require_option_value "$1" "$#"
      SELECTED_REVIEWERS+=("${2:-}")
      shift 2
      ;;
    --adversarial-evaluator)
      require_option_value "$1" "$#"
      ADVERSARIAL_EVALUATOR="${2:-}"
      shift 2
      ;;
    --allow-partial-review)
      ALLOW_PARTIAL_REVIEW="true"
      shift
      ;;
    --manual-handoff-only)
      MANUAL_HANDOFF_ONLY="true"
      shift
      ;;
    --ingest-manual-responses)
      INGEST_MANUAL_RESPONSES="true"
      shift
      ;;
    --primary-model|--antigravity-model)
      require_option_value "$1" "$#"
      PRIMARY_MODEL="${2:-}"
      PRIMARY_MODEL_EXPLICIT="true"
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

# Normalize task phase for provenance and future phase-aware route policy.
TASK_PHASE_NORM="$(printf "%s" "${TASK_PHASE:-$DEFAULT_TASK_PHASE}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
case "$TASK_PHASE_NORM" in
  planning|review|code|implementation) ;;
  *)
    echo "[ERROR] Invalid --task-phase: ${TASK_PHASE} (use planning, review, code, or implementation)" >&2
    exit 1
    ;;
esac

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
if [[ "$PRIMARY_MODEL_EXPLICIT" != "true" ]]; then
  PRIMARY_MODEL="$(primary_model_for_tool "$PRIMARY_TOOL")"
fi
if [[ -z "$RISK_PREFLIGHT_STATUS" ]]; then
  echo "[ERROR] --risk-preflight-status is required before external reviewers can be invoked" >&2
  exit 1
fi
validate_risk_preflight_status "$RISK_PREFLIGHT_STATUS"
if [[ "$RISK_PREFLIGHT_STATUS" == "blocked" || "$RISK_PREFLIGHT_STATUS" == "approval_required" ]]; then
  echo "[BLOCKED] Risk preflight status=${RISK_PREFLIGHT_STATUS}; external review is stopped before orchestration/delegation. Provide approval and rerun with --risk-preflight-status approved --approval-ref <ref> --approved-next-step <step>." >&2
  exit 1
fi
if [[ "$RISK_PREFLIGHT_STATUS" == "pass" ]]; then
  echo "[BLOCKED] External CLI review requires explicit user approval provenance; rerun with --risk-preflight-status approved --approval-ref <ref> --approved-next-step <step>." >&2
  exit 1
fi
validate_risk_preflight_recorder "$RISK_PREFLIGHT_RECORDED_BY"
if [[ -z "$RISK_PREFLIGHT_SUMMARY" ]]; then
  RISK_PREFLIGHT_SUMMARY="Main-thread risk preflight cleared this external review round."
fi
if [[ "$RISK_PREFLIGHT_STATUS" == "approved" ]]; then
  if is_placeholder_approval_value "$APPROVAL_REF" || is_placeholder_approval_value "$APPROVED_NEXT_STEP"; then
    echo "[ERROR] Concrete --approval-ref and --approved-next-step are required when --risk-preflight-status approved" >&2
    exit 1
  fi
else
  APPROVAL_REF="${APPROVAL_REF:-not_required}"
  APPROVED_NEXT_STEP="${APPROVED_NEXT_STEP:-external review ${TASK_ID} ${PLAN_VERSION} ${REVIEW_ROUND}}"
fi
if [[ "$MANUAL_HANDOFF_ONLY" == "true" && "$INGEST_MANUAL_RESPONSES" == "true" ]]; then
  echo "[ERROR] --manual-handoff-only and --ingest-manual-responses are mutually exclusive" >&2
  exit 1
fi

source "$THIS_DIR/codeguide_paths.sh"

PROJECT_ROOT_ABS="$(codeguide_resolve_project_root "$PROJECT_ROOT")"
CONTEXT_ROOT="$(codeguide_context_root "$PROJECT_ROOT_ABS")"
DOCS_DIR="$(codeguide_docs_root "$PROJECT_ROOT_ABS")"
TASK_DIR="$DOCS_DIR/task"
DECISIONS_DIR="$DOCS_DIR/decisions"
PLAN_DIR="$DOCS_DIR/plan"
REPORT_DIR="$DOCS_DIR/report"
ORCHESTRATION_DIR="$(codeguide_orchestration_root "$PROJECT_ROOT_ABS")"
ORCHESTRATION_TEMPLATES_DIR="$(codeguide_orchestration_templates_dir "$PROJECT_ROOT_ABS")"
HANDOFF_DIR="$(codeguide_external_cli_dir "$PROJECT_ROOT_ABS" "$TASK_ID" "$PLAN_VERSION" "$REVIEW_ROUND")"

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

redact_secrets_to_file() {
  local source_file="$1"
  local target_file="$2"

  perl -0pe '
    s/sk-[A-Za-z0-9_-]{20,}/[REDACTED_SECRET]/g;
    s/ghp_[A-Za-z0-9]{20,}/[REDACTED_SECRET]/g;
    s/AKIA[0-9A-Z]{16}/[REDACTED_AWS_ACCESS_KEY]/g;
    s/-----BEGIN (?:RSA|EC|OPENSSH|PRIVATE) KEY-----.*?-----END (?:RSA|EC|OPENSSH|PRIVATE) KEY-----/[REDACTED_PRIVATE_KEY]/gs;
    s/((?:api[_-]?key|token|password|secret|private[_-]?key)\s*[:=]\s*)(?:"[^"\n]{6,}"|'\''[^'\''\n]{6,}'\''|[^\s\n]{6,})/${1}[REDACTED_SECRET]/gi;
  ' "$source_file" > "$target_file"
}

ensure_handoff_path() {
  local file_path="$1"
  local label="$2"
  local parent_dir
  local parent_abs
  local handoff_abs

  parent_dir="$(dirname "$file_path")"
  parent_abs="$(cd "$parent_dir" && pwd)"
  handoff_abs="$(cd "$HANDOFF_DIR" && pwd)"

  case "${parent_abs}/" in
    "${handoff_abs}/"*) ;;
    *)
      echo "[ERROR] ${label} must stay under handoff directory: ${file_path}" >&2
      exit 1
      ;;
  esac
}

response_has_unsupported_save_location_claim() {
  local response_file="$1"
  local command_response_file="$2"
  local sanitized_response_file="$3"
  local line
  local lower

  while IFS= read -r line; do
    lower="$(printf "%s" "$line" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lower" =~ (saved|wrote|written|stored|created|저장) ]] && [[ "$line" =~ (/|\.md) ]]; then
      if [[ "$line" != *"$command_response_file"* && "$line" != *"$sanitized_response_file"* ]]; then
        return 0
      fi
    fi
  done < "$response_file"

  return 1
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
  local template_file="$ORCHESTRATION_TEMPLATES_DIR/ORCH.md"

  if [[ -f "$orchestration_file" ]]; then
    return
  fi

  mkdir -p "$(dirname "$orchestration_file")"

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
- primary_author_tool: antigravity | agy | claude | codex | human | external-runner
- review_mode: external_cli | current_task_debate | agy_subagents
- supervisor_agent:
- planner_agents:
- reviewer_agents:
- implementation_agents:
- validation_agents:
- owned_scopes:
- delegation_status: planned | active | completed | blocked
- delegation_note:
- risk_preflight_status: pass | approved | blocked | approval_required
- risk_preflight_recorded_by:
- risk_preflight_summary:
- approval_required: true | false
- approval_ref:
- approved_next_step:
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

ORCHESTRATION_FILE="$(codeguide_orchestration_file "$PROJECT_ROOT_ABS" "$TASK_ID")"
ensure_orchestration_file "$ORCHESTRATION_FILE"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
upsert_field "$ORCHESTRATION_FILE" "task_id" "$TASK_ID"
upsert_field "$ORCHESTRATION_FILE" "execution_mode" "supervisor_subagents"
upsert_field "$ORCHESTRATION_FILE" "primary_author_tool" "$PRIMARY_TOOL"
upsert_field "$ORCHESTRATION_FILE" "review_mode" "external_cli"
upsert_field_if_blank "$ORCHESTRATION_FILE" "supervisor_agent" "$RISK_PREFLIGHT_RECORDED_BY"
upsert_field "$ORCHESTRATION_FILE" "risk_preflight_status" "$RISK_PREFLIGHT_STATUS"
upsert_field "$ORCHESTRATION_FILE" "risk_preflight_recorded_by" "$RISK_PREFLIGHT_RECORDED_BY"
upsert_field "$ORCHESTRATION_FILE" "risk_preflight_summary" "$RISK_PREFLIGHT_SUMMARY"
if [[ "$RISK_PREFLIGHT_STATUS" == "approved" ]]; then
  upsert_field "$ORCHESTRATION_FILE" "approval_required" "true"
else
  upsert_field "$ORCHESTRATION_FILE" "approval_required" "false"
fi
upsert_field "$ORCHESTRATION_FILE" "approval_ref" "$APPROVAL_REF"
upsert_field "$ORCHESTRATION_FILE" "approved_next_step" "$APPROVED_NEXT_STEP"
upsert_field "$ORCHESTRATION_FILE" "last_updated" "$NOW_UTC"

# Default reviewer model aliases are registry-owned. The primary model is used
# only to prevent self-review; it does not make this wrapper the coordinator.
PRIMARY_RESOLVED="$(require_registered_model "primary_model" "$PRIMARY_MODEL")"

REVIEWERS=()
REVIEWER_COUNT=0
if (( ${#SELECTED_REVIEWERS[@]} > 0 )); then
  for alias in "${SELECTED_REVIEWERS[@]}"; do
    resolved="$(require_registered_model "reviewer" "$alias")"
    if [[ "$resolved" == "$PRIMARY_RESOLVED" ]]; then
      echo "[ERROR] --reviewer model '${alias}' resolves to the same model as --primary-model ('${PRIMARY_RESOLVED}')" >&2
      exit 1
    fi
    already_selected="false"
    for (( reviewer_index=0; reviewer_index<REVIEWER_COUNT; reviewer_index++ )); do
      if [[ "${REVIEWERS[$reviewer_index]}" == "$resolved" ]]; then
        already_selected="true"
        break
      fi
    done
    if [[ "$already_selected" == "false" ]]; then
      REVIEWERS+=("$resolved")
      REVIEWER_COUNT=$((REVIEWER_COUNT + 1))
    fi
  done
else
  for alias in "${DEFAULT_REVIEWER_ALIASES[@]}"; do
    resolved="$(require_registered_model "default_reviewer" "$alias")"
    if [[ "$resolved" != "$PRIMARY_RESOLVED" ]]; then
      REVIEWERS+=("$resolved")
      REVIEWER_COUNT=$((REVIEWER_COUNT + 1))
    fi
  done
fi

if (( REVIEWER_COUNT == 0 )); then
  echo "[ERROR] At least one non-primary reviewer is required" >&2
  exit 1
fi

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
  adversarial_resolved="$(require_registered_model "adversarial_evaluator" "$ADVERSARIAL_EVALUATOR")"
  for tool in "${REVIEWERS[@]}"; do
    if [[ "$tool" == "$adversarial_resolved" ]]; then
      found="true"
      break
    fi
  done
  if [[ "$found" != "true" ]]; then
    echo "[ERROR] adversarial evaluator must be one of the non-primary reviewers: ${REVIEWERS[*]}" >&2
    exit 1
  fi
  ADVERSARIAL_EVALUATOR="$adversarial_resolved"
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
  local command_response_file="$3"
  local evaluator="$4"
  local review_style="$5"
  local strict_retry="${6:-false}"
  local raw_request_file

  raw_request_file="$(mktemp)"
  register_tmp_file "$raw_request_file"

  cat > "$raw_request_file" <<EOF
# External plan review request (${evaluator})

- task_id: ${TASK_ID}
- plan_version: ${PLAN_VERSION}
- evaluator: ${evaluator}
- review_style: ${review_style}
- review_round: ${REVIEW_ROUND}
- primary_author_tool: ${PRIMARY_TOOL}
- source_plan_file: ${PLAN_FILE}
- expected_response_file: ${response_file}
- command_response_path: ${command_response_file}
- sanitized_response_file: ${response_file}

## Why

- Collect an evidence-based external review without passing a long prompt through shell arguments.
- Preserve the redacted request and sanitized response as Markdown orchestration artifacts.

## What

- Review PLAN-${TASK_ID}-${PLAN_VERSION} as ${evaluator} in ${review_style} mode for round ${REVIEW_ROUND}.
- Return only the parser-compatible Markdown bullet fields requested in the instructions.

## How

- Use the detailed output contract below exactly.
- Keep every field value on one line so the wrapper can normalize the response into docs/report/.
- Prefer concrete defects, missing safeguards, and verification gaps over approval-oriented feedback.
- Treat command_response_path as the only valid command output path; the wrapper sanitizes it into sanitized_response_file.

### Detailed Instructions

$(build_prompt "$evaluator" "$review_style" "$strict_retry")

## Where

- Source plan file: ${PLAN_FILE}
- Command-level response path: ${command_response_file}
- Sanitized response file: ${response_file}
- Raw stdout/final-message capture is sanitized into the response file and the raw command-level response path is deleted.
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

  redact_secrets_to_file "$raw_request_file" "$request_file"
}

# Returns the resolved model id for a given reviewer model string.
# Reviewer entries are already resolved at assignment time; this is a passthrough.
reviewer_model_for() {
  local reviewer="$1"
  printf "%s" "$reviewer"
}

tool_bin_for() {
  local reviewer_model="$1"
  local runner_id
  runner_id="$(model_runner_for "$reviewer_model")" || return 1
  runner_binary_for "$runner_id"
}

build_tool_prompt_for() {
  local reviewer_model="$1"
  local request_file="$2"
  local output_capture_file="$3"
  local durable_response_file="$4"

  printf "Read the Markdown request file from disk at %s. Review only that handoff content unless it explicitly asks for another source. Return only the requested markdown bullet fields; do not write files. Command-level response path: %s. Sanitized response file: %s. The wrapper captures the command-level response path, sanitizes it, and deletes the raw capture. Do not claim the review was saved anywhere else." \
    "$request_file" "$output_capture_file" "$durable_response_file"
}

append_quoted_command() {
  local command_file="$1"
  shift
  local arg
  for arg in "$@"; do
    printf "%q " "$arg" >> "$command_file"
  done
}

TOOL_COMMAND=()

build_tool_command() {
  local reviewer_model="$1"
  local request_file="$2"
  local output_capture_file="$3"
  local durable_response_file="$4"
  local runner_id
  local command_kind
  local binary
  local prompt

  runner_id="$(model_runner_for "$reviewer_model")" || return 1
  command_kind="$(runner_command_kind_for "$runner_id")" || return 1
  binary="$(runner_binary_for "$runner_id")" || return 1
  prompt="$(build_tool_prompt_for "$reviewer_model" "$request_file" "$output_capture_file" "$durable_response_file")"

  case "$command_kind" in
    agy)
      TOOL_COMMAND=("$binary" --add-dir "$CONTEXT_ROOT" -p "$prompt")
      ;;
    claude_code)
      TOOL_COMMAND=("$binary" -p "$prompt" --no-session-persistence --tools "" --add-dir "$CONTEXT_ROOT")
      ;;
    codex_cli)
      TOOL_COMMAND=("$binary" exec --cd "$CONTEXT_ROOT" --sandbox read-only --ephemeral --output-last-message "$output_capture_file" "$prompt")
      ;;
    *)
      echo "[ERROR] Unsupported runner command_kind '${command_kind}' for route '${reviewer_model}'" >&2
      return 1
      ;;
  esac
}

run_agy_tool_command() {
  local _model="$1"
  local output_capture_file="$2"
  local model_stderr_file="$3"
  # agy has no documented per-call model flag; use the model already selected in Antigravity.
  "${TOOL_COMMAND[@]}" >"$output_capture_file" 2>"$model_stderr_file"
}

run_codex_tool_command() {
  local _model="$1"
  local output_capture_file="$2"
  local model_stderr_file="$3"
  local runtime_stdout
  local status

  runtime_stdout="$(mktemp)"
  register_tmp_file "$runtime_stdout"

  "${TOOL_COMMAND[@]}" >"$runtime_stdout" 2>"$model_stderr_file"
  status=$?
  if [[ -s "$runtime_stdout" ]]; then
    cat "$runtime_stdout" >> "$model_stderr_file"
  fi
  if (( status != 0 )); then
    return "$status"
  fi
  if [[ ! -s "$output_capture_file" ]]; then
    echo "[ERROR] codex final message file was empty: ${output_capture_file}" >>"$model_stderr_file"
    return 1
  fi
  return 0
}

write_manual_command_file() {
  local reviewer_model="$1"
  local request_file="$2"
  local output_capture_file="$3"
  local stderr_file="$4"
  local durable_response_file="$5"
  local command_file="$6"
  local runner_id
  local cli_model
  local model_selection
  local -a cmd

  runner_id="$(model_runner_for "$reviewer_model")"
  cli_model="$(model_cli_model_for "$reviewer_model")"
  model_selection="$(model_selection_for_model "$reviewer_model")"
  build_tool_command "$reviewer_model" "$request_file" "$output_capture_file" "$durable_response_file"
  cmd=("${TOOL_COMMAND[@]}")

  cat > "$command_file" <<EOF
# Manual external review command (${runner_id}/${reviewer_model})

- task_id: ${TASK_ID}
- plan_version: ${PLAN_VERSION}
- review_round: ${REVIEW_ROUND}
- evaluator: ${runner_id}
- evaluator_route: ${reviewer_model}
- evaluator_cli_model: ${cli_model}
- evaluator_model_selection: ${model_selection}
- request_file: ${request_file}
- command_response_path: ${output_capture_file}
- sanitized_response_file: ${durable_response_file}
- stderr_file: ${stderr_file}
- follow_up: rerun run_external_plan_reviews.sh with the same options plus --ingest-manual-responses

Run this only as a last-resort fallback when the escalation layer blocks private workspace egress. This is a user-operated handoff.

\`\`\`bash
cd $(printf "%q" "$CONTEXT_ROOT")
EOF

  append_quoted_command "$command_file" "${cmd[@]}"
  printf ">%q 2>%q\n" "$output_capture_file" "$stderr_file" >> "$command_file"
  cat >> "$command_file" <<EOF
\`\`\`

After every requested reviewer has produced a raw response, run the wrapper again with \`--ingest-manual-responses\` so it can redact, parse, write reports, and generate provenance.
EOF
}

# Execute the configured runner for a given resolved model route.
# On quota exhaustion, stop and ask the user to switch the runner's global model.
# Outputs: sets ACTUAL_MODEL and QUOTA_FALLBACK_TRIGGERED.
ACTUAL_MODEL=""
QUOTA_FALLBACK_TRIGGERED="false"

run_tool_prompt() {
  local reviewer_model="$1"
  local request_file="$2"
  local output_capture_file="$3"
  local stderr_file="$4"
  local durable_response_file="${5:-$output_capture_file}"
  local run_status=0

  ACTUAL_MODEL="$reviewer_model"
  QUOTA_FALLBACK_TRIGGERED="false"

  _run_model_route() {
    local model="$1"
    local model_stderr_file="${2:-$stderr_file}"
    local binary
    local runner_id

    if ! build_tool_command "$model" "$request_file" "$output_capture_file" "$durable_response_file"; then
      echo "[ERROR] Could not build runner command for route '${model}'" > "$model_stderr_file"
      return 1
    fi
    binary="${TOOL_COMMAND[0]}"
    runner_id="$(model_runner_for "$model")"
    if ! command -v "$binary" >/dev/null 2>&1; then
      echo "[ERROR] runner '${runner_id}' binary not found in PATH: ${binary}" > "$model_stderr_file"
      return 127
    fi
    if [[ "$runner_id" == "agy" ]]; then
      run_agy_tool_command "$model" "$output_capture_file" "$model_stderr_file"
    elif [[ "$runner_id" == "codex" ]]; then
      run_codex_tool_command "$model" "$output_capture_file" "$model_stderr_file"
    else
      "${TOOL_COMMAND[@]}" >"$output_capture_file" 2>"$model_stderr_file"
    fi
  }

  if _run_model_route "$reviewer_model" "$stderr_file"; then
    return 0
  fi
  run_status=$?

  # Check for quota exhaustion and stop for user-selected model switching.
  if is_quota_exhausted "$stderr_file"; then
    local quota_group
    quota_group="$(quota_group_for_model "$reviewer_model")"
    quota_exhausted_message "$reviewer_model" "$quota_group" >&2
    return 1
  fi

  return "$run_status"
}

preserve_stderr_if_needed() {
  local temp_stderr_file="$1"
  local durable_stderr_file="$2"
  local status="$3"

  if [[ "$status" -ne 0 || -s "$temp_stderr_file" ]]; then
    redact_secrets_to_file "$temp_stderr_file" "$durable_stderr_file"
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

file_sha256_ref() {
  local file_path="$1"
  local digest

  digest="$(shasum -a 256 "$file_path" | awk '{print $1}')"
  printf "sha256:%s" "$digest"
}

write_response_provenance_file() {
  local evaluator_requested_model="$1"
  local review_style="$2"
  local response_file="$3"
  local request_file="$4"
  local command_response_file="$5"
  local evaluator_actual_model="${6:-$evaluator_requested_model}"
  local quota_fallback="${7:-false}"
  local provenance_file
  local now_utc
  local response_hash
  local evaluator_requested_runner
  local evaluator_actual_runner
  local evaluator_requested_cli_model
  local evaluator_actual_cli_model
  local evaluator_model_selection

  provenance_file="${response_file%.md}.provenance.md"
  ensure_handoff_path "$provenance_file" "response_provenance_file"
  now_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  response_hash="$(file_sha256_ref "$response_file")"
  evaluator_requested_runner="$(model_runner_for "$evaluator_requested_model")"
  evaluator_actual_runner="$(model_runner_for "$evaluator_actual_model")"
  evaluator_requested_cli_model="$(model_cli_model_for "$evaluator_requested_model")"
  evaluator_actual_cli_model="$(model_cli_model_for "$evaluator_actual_model")"
  evaluator_model_selection="$(model_selection_for_model "$evaluator_actual_model")"

  cat > "$provenance_file" <<EOF
# External CLI Review Response Provenance

- artifact_kind: external_cli_review_response_provenance
- generated_by: run_external_plan_reviews.sh
- generated_at: ${now_utc}
- task_id: ${TASK_ID}
- plan_version: ${PLAN_VERSION}
- review_round: ${REVIEW_ROUND}
- evaluator: ${evaluator_actual_runner}
- evaluator_requested_runner: ${evaluator_requested_runner}
- evaluator_actual_runner: ${evaluator_actual_runner}
- evaluator_requested_route: ${evaluator_requested_model}
- evaluator_actual_route: ${evaluator_actual_model}
- evaluator_requested_model: ${evaluator_requested_model}
- evaluator_actual_model: ${evaluator_actual_model}
- evaluator_requested_cli_model: ${evaluator_requested_cli_model}
- evaluator_actual_cli_model: ${evaluator_actual_cli_model}
- evaluator_model_selection: ${evaluator_model_selection}
- quota_fallback_triggered: ${quota_fallback}
- review_style: ${review_style}
- verdict: ${PARSED_VERDICT}
- request_file: ${request_file}
- response_file: ${response_file}
- response_sha256: ${response_hash}
- command_response_path: ${command_response_file}
- raw_capture_deleted: true
- sanitized_response: true
EOF
}

write_report_file() {
  local evaluator_requested_model="$1"
  local review_style="$2"
  local report_file="$3"
  local evaluator_actual_model="${4:-$evaluator_requested_model}"
  local quota_fallback="${5:-false}"
  local now_utc
  local evaluator_requested_runner
  local evaluator_actual_runner
  local evaluator_requested_cli_model
  local evaluator_actual_cli_model
  local evaluator_model_selection

  now_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  evaluator_requested_runner="$(model_runner_for "$evaluator_requested_model")"
  evaluator_actual_runner="$(model_runner_for "$evaluator_actual_model")"
  evaluator_requested_cli_model="$(model_cli_model_for "$evaluator_requested_model")"
  evaluator_actual_cli_model="$(model_cli_model_for "$evaluator_actual_model")"
  evaluator_model_selection="$(model_selection_for_model "$evaluator_actual_model")"
  cat > "$report_file" <<EOF
# PLAN-${TASK_ID}-${PLAN_VERSION} review (${evaluator_actual_runner}/${evaluator_actual_model})

- task_id: ${TASK_ID}
- plan_version: ${PLAN_VERSION}
- evaluator: ${evaluator_actual_runner}
- evaluator_requested_runner: ${evaluator_requested_runner}
- evaluator_actual_runner: ${evaluator_actual_runner}
- evaluator_requested_route: ${evaluator_requested_model}
- evaluator_actual_route: ${evaluator_actual_model}
- evaluator_requested_model: ${evaluator_requested_model}
- evaluator_actual_model: ${evaluator_actual_model}
- evaluator_requested_cli_model: ${evaluator_requested_cli_model}
- evaluator_actual_cli_model: ${evaluator_actual_cli_model}
- evaluator_model_selection: ${evaluator_model_selection}
- quota_fallback_triggered: ${quota_fallback}
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
  # reviewer is already a registry-resolved runner-qualified model route.
  # Use a filesystem-safe slug derived from the model id for file naming.
  reviewer_runner="$(model_runner_for "$reviewer")"
  reviewer_slug="$(printf "%s" "$reviewer" | sed 's/[^A-Za-z0-9._-]/-/g')"
  review_style="standard"
  if [[ -n "$ADVERSARIAL_EVALUATOR" ]]; then
    adversarial_resolved="$(resolve_model_name "$ADVERSARIAL_EVALUATOR")"
    if [[ "$reviewer" == "$adversarial_resolved" ]]; then
      review_style="adversarial"
    fi
  fi

  report_file="$REPORT_DIR/PLAN-${TASK_ID}-${PLAN_VERSION}-review-${reviewer_slug}-${REVIEW_ROUND}.md"
  if [[ -f "$report_file" ]]; then
    stale_file="${report_file}.stale-${NOW_UTC}"
    mv "$report_file" "$stale_file"
  fi

  request_file="$HANDOFF_DIR/${reviewer_slug}.request.md"
  response_file="$HANDOFF_DIR/${reviewer_slug}.response.md"
  response_raw_file="$HANDOFF_DIR/${reviewer_slug}.command-response.raw.md"
  stderr_durable_file="$HANDOFF_DIR/${reviewer_slug}.stderr.md"
  manual_command_file="$HANDOFF_DIR/${reviewer_slug}.manual-command.md"
  active_stderr_durable_file="$stderr_durable_file"
  stderr_file="$(mktemp)"
  register_tmp_file "$stderr_file"
  if [[ "$MANUAL_HANDOFF_ONLY" != "true" && "$INGEST_MANUAL_RESPONSES" != "true" ]]; then
    register_tmp_file "$response_raw_file"
  fi

  ensure_handoff_path "$request_file" "request_file"
  ensure_handoff_path "$response_file" "response_file"
  ensure_handoff_path "$response_raw_file" "command_response_path"
  ensure_handoff_path "$stderr_durable_file" "stderr_file"

  if [[ "$INGEST_MANUAL_RESPONSES" == "true" ]]; then
    effective_request_file="$request_file"
    effective_response_raw_file="$response_raw_file"
    if [[ ! -f "$request_file" ]]; then
      run_status=64
      echo "[ERROR] manual ingest requires existing request file: ${request_file}" > "$stderr_file"
    elif [[ -s "$response_raw_file" ]]; then
      redact_secrets_to_file "$response_raw_file" "$response_file"
      rm -f "$response_raw_file" 2>/dev/null || true
      run_status=0
    elif [[ -s "$response_file" ]]; then
      run_status=0
    else
      run_status=65
      echo "[ERROR] manual ingest requires raw response or sanitized response file for ${reviewer_slug}: ${response_raw_file} or ${response_file}" > "$stderr_file"
    fi
    preserve_stderr_if_needed "$stderr_file" "$stderr_durable_file" "$run_status"
    if [[ "$run_status" -eq 0 ]] && parse_review_response "$response_file" "$review_style"; then
      write_response_provenance_file "$reviewer" "$review_style" "$response_file" "$effective_request_file" "$effective_response_raw_file" "$reviewer" "false"
      write_report_file "$reviewer" "$review_style" "$report_file" "$reviewer" "false"
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
      if [[ "$review_style" == "adversarial" ]]; then
        ADVERSARIAL_SUCCESS="true"
      fi
      STATUS_LINES+=("[OK] evaluator=${reviewer_runner} route=${reviewer} style=${review_style} verdict=${PARSED_VERDICT} file=${report_file} summary=$(normalize_one_line "$PARSED_SUMMARY")")
    else
      FAIL_COUNT=$((FAIL_COUNT + 1))
      failure_reason="$(normalize_one_line "$(cat "$active_stderr_durable_file" 2>/dev/null || cat "$stderr_file" 2>/dev/null || true)")"
      if [[ -z "$failure_reason" ]]; then
        failure_reason="manual response missing required fields"
      fi
      STATUS_LINES+=("[FAIL] evaluator=${reviewer_runner} route=${reviewer} style=${review_style} reason=${failure_reason}")
    fi
    continue
  fi

  rm -f "$request_file" "$response_file" "$stderr_durable_file" \
    "$response_raw_file" \
    "$manual_command_file" \
    "$HANDOFF_DIR/${reviewer_slug}.retry-request.md" \
    "$HANDOFF_DIR/${reviewer_slug}.retry-response.md" \
    "$HANDOFF_DIR/${reviewer_slug}.response.provenance.md" \
    "$HANDOFF_DIR/${reviewer_slug}.retry-response.provenance.md" \
    "$HANDOFF_DIR/${reviewer_slug}.retry-command-response.raw.md" \
    "$HANDOFF_DIR/${reviewer_slug}.retry-stderr.md"

  write_handoff_request "$request_file" "$response_file" "$response_raw_file" "$reviewer" "$review_style" "false"
  effective_request_file="$request_file"
  effective_response_raw_file="$response_raw_file"

  if [[ "$MANUAL_HANDOFF_ONLY" == "true" ]]; then
    write_manual_command_file "$reviewer" "$request_file" "$response_raw_file" "$stderr_durable_file" "$response_file" "$manual_command_file"
    STATUS_LINES+=("[MANUAL] evaluator=${reviewer_runner} route=${reviewer} style=${review_style} request=${request_file} command_file=${manual_command_file} raw_response=${response_raw_file}")
    continue
  fi

  : > "$response_raw_file"
  run_status=0
  if run_tool_prompt "$reviewer" "$request_file" "$response_raw_file" "$stderr_file" "$response_file"; then
    run_status=0
  else
    run_status=$?
  fi
  redact_secrets_to_file "$response_raw_file" "$response_file"
  rm -f "$response_raw_file" 2>/dev/null || true
  preserve_stderr_if_needed "$stderr_file" "$stderr_durable_file" "$run_status"

  invalid_response_claim="false"
  if [[ "$run_status" -eq 0 ]] && response_has_unsupported_save_location_claim "$response_file" "$response_raw_file" "$response_file"; then
    echo "[ERROR] ${reviewer} response contains unsupported save-location claim" >> "$stderr_file"
    preserve_stderr_if_needed "$stderr_file" "$stderr_durable_file" 65
    invalid_response_claim="true"
  fi

  if [[ "$run_status" -eq 0 && "$invalid_response_claim" == "false" ]] && parse_review_response "$response_file" "$review_style"; then
    :
  elif [[ "$run_status" -eq 0 ]]; then
    retry_request_file="$HANDOFF_DIR/${reviewer_slug}.retry-request.md"
    retry_response_file="$HANDOFF_DIR/${reviewer_slug}.retry-response.md"
    retry_response_raw_file="$HANDOFF_DIR/${reviewer_slug}.retry-command-response.raw.md"
    retry_stderr_durable_file="$HANDOFF_DIR/${reviewer_slug}.retry-stderr.md"
    retry_stderr="$(mktemp)"
    register_tmp_file "$retry_response_raw_file"
    register_tmp_file "$retry_stderr"
    ensure_handoff_path "$retry_request_file" "retry_request_file"
    ensure_handoff_path "$retry_response_file" "retry_response_file"
    ensure_handoff_path "$retry_response_raw_file" "retry_command_response_path"
    ensure_handoff_path "$retry_stderr_durable_file" "retry_stderr_file"
    rm -f "$retry_response_raw_file"
    write_handoff_request "$retry_request_file" "$retry_response_file" "$retry_response_raw_file" "$reviewer" "$review_style" "true"
    : > "$retry_response_raw_file"
    retry_status=0
    if run_tool_prompt "$reviewer" "$retry_request_file" "$retry_response_raw_file" "$retry_stderr" "$retry_response_file"; then
      retry_status=0
    else
      retry_status=$?
    fi
    redact_secrets_to_file "$retry_response_raw_file" "$retry_response_file"
    rm -f "$retry_response_raw_file" 2>/dev/null || true
    preserve_stderr_if_needed "$retry_stderr" "$retry_stderr_durable_file" "$retry_status"

    retry_invalid_response_claim="false"
    if [[ "$retry_status" -eq 0 ]] && response_has_unsupported_save_location_claim "$retry_response_file" "$retry_response_raw_file" "$retry_response_file"; then
      echo "[ERROR] ${reviewer} retry response contains unsupported save-location claim" >> "$retry_stderr"
      preserve_stderr_if_needed "$retry_stderr" "$retry_stderr_durable_file" 65
      retry_invalid_response_claim="true"
    fi

    if [[ "$retry_status" -eq 0 && "$retry_invalid_response_claim" == "false" ]] && parse_review_response "$retry_response_file" "$review_style"; then
      response_file="$retry_response_file"
      effective_request_file="$retry_request_file"
      effective_response_raw_file="$retry_response_raw_file"
      stderr_file="$retry_stderr"
      active_stderr_durable_file="$retry_stderr_durable_file"
      run_status=0
    else
      run_status=65
      if [[ "$retry_status" -ne 0 ]]; then
        stderr_file="$retry_stderr"
        active_stderr_durable_file="$retry_stderr_durable_file"
      fi
    fi
  fi

  if [[ "$run_status" -eq 0 ]]; then
    actual_runner="$(model_runner_for "$ACTUAL_MODEL")"
    write_response_provenance_file "$reviewer" "$review_style" "$response_file" "$effective_request_file" "$effective_response_raw_file" "$ACTUAL_MODEL" "$QUOTA_FALLBACK_TRIGGERED"
    write_report_file "$reviewer" "$review_style" "$report_file" "$ACTUAL_MODEL" "$QUOTA_FALLBACK_TRIGGERED"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    if [[ "$review_style" == "adversarial" ]]; then
      ADVERSARIAL_SUCCESS="true"
    fi
    STATUS_LINES+=("[OK] evaluator=${actual_runner} requested_route=${reviewer} actual_route=${ACTUAL_MODEL} quota_fallback=${QUOTA_FALLBACK_TRIGGERED} style=${review_style} verdict=${PARSED_VERDICT} file=${report_file} summary=$(normalize_one_line "$PARSED_SUMMARY")")
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    failure_reason="$(normalize_one_line "$(cat "$active_stderr_durable_file" 2>/dev/null || cat "$stderr_file" 2>/dev/null || true)")"
    if [[ -z "$failure_reason" ]]; then
      failure_reason="response missing required fields"
    fi
    STATUS_LINES+=("[FAIL] evaluator=${reviewer_runner} route=${reviewer} style=${review_style} reason=${failure_reason}")
  fi
done

printf "%s\n" "${STATUS_LINES[@]}"
echo "[INFO] review_successes=${SUCCESS_COUNT} review_failures=${FAIL_COUNT}"
echo "[INFO] Semi-automated stop reached. No new plan version was created automatically."

if [[ "$MANUAL_HANDOFF_ONLY" == "true" ]]; then
  echo "[INFO] manual_handoff_only=true; no external CLI was invoked."
  echo "[INFO] Run the generated *.manual-command.md commands yourself, then rerun this wrapper with --ingest-manual-responses."
  exit 0
fi

if [[ -n "$ADVERSARIAL_EVALUATOR" && "$ADVERSARIAL_SUCCESS" != "true" ]]; then
  echo "[ERROR] Required adversarial review did not complete successfully for evaluator=${ADVERSARIAL_EVALUATOR}" >&2
  exit 1
fi

if [[ "$SUCCESS_COUNT" -eq "$REVIEWER_COUNT" ]]; then
  exit 0
fi

if [[ "$SUCCESS_COUNT" -gt 0 && "$ALLOW_PARTIAL_REVIEW" == "true" ]]; then
  echo "[WARN] Partial external review accepted by --allow-partial-review; successful reviewers=${SUCCESS_COUNT}/${REVIEWER_COUNT}." >&2
  exit 0
fi

if [[ "$SUCCESS_COUNT" -gt 0 ]]; then
  echo "[ERROR] External review round incomplete: successful reviewers=${SUCCESS_COUNT}/${REVIEWER_COUNT}. Rerun failed reviewers or pass --allow-partial-review to accept a partial round explicitly." >&2
fi

exit 1
