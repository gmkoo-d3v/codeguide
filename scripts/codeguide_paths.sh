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

codeguide_source_root() {
  # Resolve the git repository that owns the project's SOURCE code, as opposed
  # to the docs system-of-record root. In the reusable-skills layout the docs
  # root sits one level ABOVE the skill's own repo (and may itself be a
  # docs-only local repo), so git operations must not target the docs root.
  # CODEGUIDE_SOURCE_ROOT overrides all detection for ambiguous layouts.
  local input_root="$1"
  local input_abs
  local git_root
  local project_root
  local candidate=""
  local child

  # Emit physical paths from every branch: git prints physical toplevels, so
  # scan-derived results must match (macOS /var vs /private/var).
  if [[ -n "${CODEGUIDE_SOURCE_ROOT:-}" ]]; then
    (cd "$CODEGUIDE_SOURCE_ROOT" 2>/dev/null && pwd -P) && return 0
    echo "[WARN] CODEGUIDE_SOURCE_ROOT is not a readable directory: ${CODEGUIDE_SOURCE_ROOT}" >&2
    return 1
  fi

  input_abs="$(cd "$input_root" && pwd -P)" || return 1
  git_root="$(git -C "$input_abs" rev-parse --show-toplevel 2>/dev/null || true)"

  if [[ -n "$git_root" ]] && codeguide_is_skill_package_root "$git_root"; then
    printf "%s" "$git_root"
    return 0
  fi

  project_root="$(codeguide_resolve_project_root "$input_root")"

  for child in "$project_root"/*/; do
    child="${child%/}"
    [[ -d "$child" && -e "$child/.git" ]] || continue
    codeguide_is_skill_package_root "$child" || continue
    if [[ -n "$candidate" ]]; then
      echo "[WARN] Multiple skill-package source repositories under ${project_root}; set CODEGUIDE_SOURCE_ROOT to disambiguate." >&2
      return 1
    fi
    candidate="$child"
  done

  if [[ -n "$candidate" ]]; then
    (cd "$candidate" && pwd -P)
    return 0
  fi

  if git -C "$project_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$project_root" rev-parse --show-toplevel
    return 0
  fi

  return 1
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
