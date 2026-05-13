#!/usr/bin/env bash

# Shared path policy for codeguide scripts.
# Keep docs under the selected project root, resolving to the git root when
# invoked from inside a repository.

codeguide_resolve_project_root() {
  local input_root="$1"
  local input_abs

  input_abs="$(cd "$input_root" && pwd)" || return 1
  git -C "$input_abs" rev-parse --show-toplevel 2>/dev/null || printf "%s" "$input_abs"
}

codeguide_docs_root() {
  local project_root_abs="$1"

  printf "%s/docs" "$project_root_abs"
}

codeguide_context_root() {
  local project_root_abs="$1"

  printf "%s" "$project_root_abs"
}
