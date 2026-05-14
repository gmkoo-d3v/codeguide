#!/usr/bin/env bash

# Shared path policy for codeguide scripts.
# Keep docs under the selected project root, resolving to the git root when
# invoked from inside a repository.

codeguide_resolve_project_root() {
  local input_root="$1"
  local input_abs
  local git_root
  local resolved_root
  local parent_root

  input_abs="$(cd "$input_root" && pwd)" || return 1
  git_root="$(git -C "$input_abs" rev-parse --show-toplevel 2>/dev/null || true)"
  resolved_root="${git_root:-$input_abs}"

  if codeguide_is_skill_package_root "$resolved_root" \
    && [[ ! -d "$resolved_root/docs" ]]; then
    parent_root="$(dirname "$resolved_root")"
    if [[ -d "$parent_root/docs" ]]; then
      printf "%s" "$parent_root"
      return 0
    fi
  fi

  printf "%s" "$resolved_root"
}

codeguide_is_skill_package_root() {
  local candidate_root="$1"

  [[ -f "$candidate_root/SKILL.md" ]] || return 1
  grep -Eq '^name:[[:space:]]*[^[:space:]]+' "$candidate_root/SKILL.md" || return 1
  [[ -d "$candidate_root/scripts" || -d "$candidate_root/references" || -d "$candidate_root/tests" ]] || return 1
}

codeguide_docs_root() {
  local project_root_abs="$1"

  printf "%s/docs" "$project_root_abs"
}

codeguide_orchestration_root() {
  local project_root_abs="$1"

  printf "%s/orchestration" "$(codeguide_docs_root "$project_root_abs")"
}

codeguide_orchestration_templates_dir() {
  local project_root_abs="$1"

  printf "%s/_templates" "$(codeguide_orchestration_root "$project_root_abs")"
}

codeguide_orchestration_task_dir() {
  local project_root_abs="$1"
  local task_id="$2"

  printf "%s/%s" "$(codeguide_orchestration_root "$project_root_abs")" "$task_id"
}

codeguide_orchestration_file() {
  local project_root_abs="$1"
  local task_id="$2"

  printf "%s/ORCH.md" "$(codeguide_orchestration_task_dir "$project_root_abs" "$task_id")"
}

codeguide_external_cli_dir() {
  local project_root_abs="$1"
  local task_id="$2"
  local plan_version="$3"
  local review_round="$4"

  printf "%s/external-cli/%s/%s" "$(codeguide_orchestration_task_dir "$project_root_abs" "$task_id")" "$plan_version" "$review_round"
}

codeguide_context_root() {
  local project_root_abs="$1"

  printf "%s" "$project_root_abs"
}
