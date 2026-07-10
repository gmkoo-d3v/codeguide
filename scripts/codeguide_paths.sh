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

codeguide_normalize_source_dir() {
  # Normalize a user-supplied source location to its git toplevel (physical
  # path). git prints toplevel-relative diff paths, so a subdirectory here
  # would silently empty every downstream change set.
  local raw_dir="$1"
  local label="$2"
  local dir_abs
  local git_root

  dir_abs="$(cd "$raw_dir" 2>/dev/null && pwd -P)" || {
    echo "[WARN] ${label} is not a readable directory: ${raw_dir}" >&2
    return 1
  }
  git_root="$(git -C "$dir_abs" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$git_root" ]]; then
    printf "%s" "$git_root"
    return 0
  fi
  echo "[WARN] ${label} is not inside a git repository; git-dependent features will be disabled: ${raw_dir}" >&2
  printf "%s" "$dir_abs"
}

codeguide_source_root() {
  # Resolve the git repository that owns the project's SOURCE code, as opposed
  # to the docs system-of-record root. Precedence, most explicit first:
  #   1. CODEGUIDE_SOURCE_ROOT (normalized to its git toplevel)
  #   2. <project-root>/.codeguide-source-root marker file naming the source
  #      repo path — the explicit contract for docs-only parent repos
  #   3. the input path's own repo when that repo is a skill package
  #   4. the project root's own enclosing repo (an ordinary project; a nested
  #      skill-package child never hijacks it)
  #   5. a unique skill-package child repo, only when the project root is not
  #      inside any repo (the classic non-git docs-parent skills layout)
  #   6. loud failure
  # Emit physical paths from every branch: git prints physical toplevels, so
  # scan-derived results must match (macOS /var vs /private/var).
  local input_root="$1"
  local input_abs
  local git_root
  local project_root
  local marker_file
  local marker_target
  local candidate=""
  local child

  if [[ -n "${CODEGUIDE_SOURCE_ROOT:-}" ]]; then
    codeguide_normalize_source_dir "$CODEGUIDE_SOURCE_ROOT" "CODEGUIDE_SOURCE_ROOT"
    return
  fi

  input_abs="$(cd "$input_root" && pwd -P)" || return 1
  project_root="$(codeguide_resolve_project_root "$input_root")"

  marker_file="$project_root/.codeguide-source-root"
  if [[ -f "$marker_file" ]]; then
    marker_target="$(head -n 1 "$marker_file")"
    marker_target="${marker_target#"${marker_target%%[![:space:]]*}"}"
    marker_target="${marker_target%"${marker_target##*[![:space:]]}"}"
    if [[ -z "$marker_target" ]]; then
      echo "[WARN] .codeguide-source-root is empty: ${marker_file}" >&2
      return 1
    fi
    [[ "$marker_target" == /* ]] || marker_target="$project_root/$marker_target"
    codeguide_normalize_source_dir "$marker_target" ".codeguide-source-root"
    return
  fi

  git_root="$(git -C "$input_abs" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$git_root" ]] && codeguide_is_skill_package_root "$git_root"; then
    printf "%s" "$git_root"
    return 0
  fi

  if git -C "$project_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    for child in "$project_root"/*/; do
      child="${child%/}"
      [[ -d "$child" && -e "$child/.git" ]] || continue
      codeguide_is_skill_package_root "$child" || continue
      echo "[INFO] Source root is the enclosing repo of ${project_root}; nested skill-package repo ${child} was not selected. For a docs-only root, declare .codeguide-source-root or set CODEGUIDE_SOURCE_ROOT." >&2
      break
    done
    git -C "$project_root" rev-parse --show-toplevel
    return 0
  fi

  for child in "$project_root"/*/; do
    child="${child%/}"
    [[ -d "$child" && -e "$child/.git" ]] || continue
    codeguide_is_skill_package_root "$child" || continue
    if [[ -n "$candidate" ]]; then
      echo "[WARN] Multiple skill-package source repositories under ${project_root}; set CODEGUIDE_SOURCE_ROOT or declare .codeguide-source-root to disambiguate." >&2
      return 1
    fi
    candidate="$child"
  done

  if [[ -n "$candidate" ]]; then
    (cd "$candidate" && pwd -P)
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
