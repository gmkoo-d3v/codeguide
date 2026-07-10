#!/usr/bin/env bats

load codeguide_helper

# Fixtures for source-root resolution. The skills layout keeps docs one level
# above the skill's own git repo, and the docs root may itself be a docs-only
# local repo; codeguide_source_root must always land on the SOURCE repo.

setup() {
  TEST_WORKSPACE="$(mktemp -d)"
  export TEST_WORKSPACE
  unset CODEGUIDE_SOURCE_ROOT
}

teardown() {
  rm -rf "$TEST_WORKSPACE"
}

physical_path() {
  (cd "$1" && pwd -P)
}

make_git_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init --quiet
}

make_skill_package() {
  local dir="$1"
  mkdir -p "$dir/scripts"
  printf -- "---\nname: fixture-skill\n---\n" > "$dir/SKILL.md"
}

make_skills_layout() {
  # parent (docs root) + nested skill-package git repo
  local parent="$1"
  mkdir -p "$parent/docs"
  make_git_repo "$parent/skillpkg"
  make_skill_package "$parent/skillpkg"
}

@test "source root: ordinary project repo resolves to its own toplevel" {
  local project="$TEST_WORKSPACE/app"
  make_git_repo "$project"
  mkdir -p "$project/docs"

  run codeguide_source_root "$project"
  [ "$status" -eq 0 ]
  [ "$output" = "$(physical_path "$project")" ]
}

@test "source root: skills layout with non-git docs root resolves to the nested skill repo" {
  local parent="$TEST_WORKSPACE/workspace"
  make_skills_layout "$parent"

  run codeguide_source_root "$parent"
  [ "$status" -eq 0 ]
  [ "$output" = "$(physical_path "$parent/skillpkg")" ]
}

@test "source root: docs-only local repo resolves to the nested skill repo via the marker file" {
  local parent="$TEST_WORKSPACE/workspace"
  make_skills_layout "$parent"
  make_git_repo "$parent"
  printf 'skillpkg\n' > "$parent/.codeguide-source-root"

  run codeguide_source_root "$parent"
  [ "$status" -eq 0 ]
  [ "$output" = "$(physical_path "$parent/skillpkg")" ]
}

@test "source root: docs-only local repo without a marker resolves to itself with a hint" {
  local parent="$TEST_WORKSPACE/workspace"
  make_skills_layout "$parent"
  make_git_repo "$parent"

  run codeguide_source_root "$parent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(physical_path "$parent")"* ]]
  [[ "$output" == *"nested skill-package repo"* ]]
  [[ "$output" == *".codeguide-source-root"* ]]
}

@test "source root: ordinary repo is never hijacked by a vendored skill-package child repo" {
  local project="$TEST_WORKSPACE/app"
  make_git_repo "$project"
  mkdir -p "$project/docs"
  make_git_repo "$project/vendored-skill"
  make_skill_package "$project/vendored-skill"

  run codeguide_source_root "$project"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(physical_path "$project")"* ]]
  [[ "$output" != *"vendored-skill"* ]] || [[ "$output" == *"was not selected"* ]]
}

@test "source root: invoked from inside the skill repo resolves to that repo" {
  local parent="$TEST_WORKSPACE/workspace"
  make_skills_layout "$parent"

  run codeguide_source_root "$parent/skillpkg/scripts"
  [ "$status" -eq 0 ]
  [ "$output" = "$(physical_path "$parent/skillpkg")" ]
}

@test "source root: no reachable repo fails with empty output" {
  local project="$TEST_WORKSPACE/plain"
  mkdir -p "$project/docs"

  run codeguide_source_root "$project"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "source root: CODEGUIDE_SOURCE_ROOT override wins over detection" {
  local parent="$TEST_WORKSPACE/workspace"
  local override="$TEST_WORKSPACE/elsewhere"
  make_skills_layout "$parent"
  make_git_repo "$override"

  CODEGUIDE_SOURCE_ROOT="$override" run codeguide_source_root "$parent"
  [ "$status" -eq 0 ]
  [ "$output" = "$(physical_path "$override")" ]
}

@test "source root: a subdirectory override normalizes to its git toplevel" {
  local parent="$TEST_WORKSPACE/workspace"
  local override="$TEST_WORKSPACE/elsewhere"
  make_skills_layout "$parent"
  make_git_repo "$override"
  mkdir -p "$override/sub/dir"

  CODEGUIDE_SOURCE_ROOT="$override/sub/dir" run codeguide_source_root "$parent"
  [ "$status" -eq 0 ]
  [ "$output" = "$(physical_path "$override")" ]
}

@test "source root: an unreadable override fails with a distinct diagnostic" {
  local parent="$TEST_WORKSPACE/workspace"
  make_skills_layout "$parent"

  CODEGUIDE_SOURCE_ROOT="$TEST_WORKSPACE/does-not-exist" run codeguide_source_root "$parent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CODEGUIDE_SOURCE_ROOT is not a readable directory"* ]]
}

@test "source root: multiple skill-package repos are ambiguous and fail loudly" {
  local parent="$TEST_WORKSPACE/workspace"
  make_skills_layout "$parent"
  make_git_repo "$parent/otherskill"
  make_skill_package "$parent/otherskill"

  run codeguide_source_root "$parent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Multiple skill-package source repositories"* ]]
}

python_source_root() {
  python3 - "$1" <<PY
import sys
from pathlib import Path
sys.path.insert(0, "$SCRIPTS_DIR")
from codeguide_paths import source_root_for
result = source_root_for(Path(sys.argv[1]))
print(result if result is not None else "")
PY
}

@test "source root (python): parity for ordinary repo, marker layout, vendored child, ambiguity, and no-repo" {
  local project="$TEST_WORKSPACE/app"
  make_git_repo "$project"
  [ "$(python_source_root "$project")" = "$(physical_path "$project")" ]

  local parent="$TEST_WORKSPACE/workspace"
  make_skills_layout "$parent"
  make_git_repo "$parent"
  printf 'skillpkg\n' > "$parent/.codeguide-source-root"
  [ "$(python_source_root "$parent")" = "$(physical_path "$parent/skillpkg")" ]

  local vendored="$TEST_WORKSPACE/vendored"
  make_git_repo "$vendored"
  make_git_repo "$vendored/vendored-skill"
  make_skill_package "$vendored/vendored-skill"
  [ "$(python_source_root "$vendored" 2>/dev/null)" = "$(physical_path "$vendored")" ]

  local multi="$TEST_WORKSPACE/multi"
  mkdir -p "$multi/docs"
  make_git_repo "$multi/skill-a"
  make_skill_package "$multi/skill-a"
  make_git_repo "$multi/skill-b"
  make_skill_package "$multi/skill-b"
  [ -z "$(python_source_root "$multi" 2>/dev/null)" ]

  local plain="$TEST_WORKSPACE/plain"
  mkdir -p "$plain"
  [ -z "$(python_source_root "$plain")" ]
}
