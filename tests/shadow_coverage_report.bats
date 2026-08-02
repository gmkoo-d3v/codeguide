#!/usr/bin/env bats

load codeguide_helper

COVERAGE() {
  python3 "$SCRIPTS_DIR/shadow_coverage_report.py" "$@"
}

_seed_project_with_coverage() {
  # $1 = source_of_truth_paths value for the one documented unit
  mkdir -p "$TEST_PROJECT/src/mod_a" "$TEST_PROJECT/src/mod_b" "$DOCS_ROOT/shadow/apps/app-a"
  printf 'a=1\n' > "$TEST_PROJECT/src/mod_a/x.py"
  printf 'b=1\n' > "$TEST_PROJECT/src/mod_b/y.py"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<EOF
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths: ${1}
- last_updated: 2026-01-01T00:00:00Z
EOF
}

@test "coverage report flags a changed source that no shadow doc documents" {
  _seed_project_with_coverage "src/mod_a"
  run COVERAGE --project-root "$TEST_PROJECT" --changed-file src/mod_b/y.py
  [ "$status" -eq 0 ]
  assert_contains "$output" "uncovered: 1"
  assert_contains "$output" "UNCOVERED: src/mod_b/y.py"
}

@test "coverage report treats a source under a documented directory as covered" {
  _seed_project_with_coverage "src/mod_a"
  run COVERAGE --project-root "$TEST_PROJECT" --changed-file src/mod_a/x.py
  [ "$status" -eq 0 ]
  assert_contains "$output" "uncovered: 0"
  assert_contains "$output" "every changed source is documented"
}

@test "coverage report treats an exactly-declared source file as covered" {
  _seed_project_with_coverage "src/mod_b/y.py"
  run COVERAGE --project-root "$TEST_PROJECT" --changed-file src/mod_b/y.py
  [ "$status" -eq 0 ]
  assert_contains "$output" "uncovered: 0"
}

@test "coverage report does not treat a changed doc as source needing coverage" {
  _seed_project_with_coverage "src/mod_a"
  run COVERAGE --project-root "$TEST_PROJECT" --changed-file docs/shadow/apps/app-a/overview.md
  [ "$status" -eq 0 ]
  assert_contains "$output" "changed_source_files: 0"
  assert_contains "$output" "no changed source files to check"
}

@test "coverage report --exit-code returns 1 when a source is uncovered" {
  _seed_project_with_coverage "src/mod_a"
  run COVERAGE --project-root "$TEST_PROJECT" --changed-file src/mod_b/y.py --exit-code
  [ "$status" -eq 1 ]
}

@test "coverage report working-tree mode flags an undocumented changed source in a git repo" {
  git -C "$TEST_PROJECT" init -q
  git -C "$TEST_PROJECT" config user.email t@example.com
  git -C "$TEST_PROJECT" config user.name t
  _seed_project_with_coverage "src/mod_a"
  git -C "$TEST_PROJECT" add -A
  git -C "$TEST_PROJECT" commit -qm init
  printf 'b=2\n' > "$TEST_PROJECT/src/mod_b/y.py"
  run COVERAGE --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "UNCOVERED: src/mod_b/y.py"
}

@test "coverage report ignores source_of_truth_paths under _deprecated" {
  mkdir -p "$TEST_PROJECT/src/mod_b" "$DOCS_ROOT/shadow/_deprecated/apps/app-a"
  printf 'b=1\n' > "$TEST_PROJECT/src/mod_b/y.py"
  cat > "$DOCS_ROOT/shadow/_deprecated/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths: src/mod_b
- last_updated: 2026-01-01T00:00:00Z
EOF
  # The only doc that "covers" src/mod_b is deprecated, so the source is uncovered.
  run COVERAGE --project-root "$TEST_PROJECT" --changed-file src/mod_b/y.py
  [ "$status" -eq 0 ]
  assert_contains "$output" "UNCOVERED: src/mod_b/y.py"
}

@test "coverage report flags an undocumented directory passed via --changed-file" {
  _seed_project_with_coverage "src/mod_a"
  run COVERAGE --project-root "$TEST_PROJECT" --changed-file src/mod_b
  [ "$status" -eq 0 ]
  assert_contains "$output" "changed_source_files: 1"
  assert_contains "$output" "UNCOVERED: src/mod_b"
}

@test "coverage report does not let a blanket '.' declaration cover the whole project" {
  _seed_project_with_coverage "src/mod_a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/blanket.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths: .
- last_updated: 2026-01-01T00:00:00Z
EOF
  run COVERAGE --project-root "$TEST_PROJECT" --changed-file src/mod_b/y.py
  [ "$status" -eq 0 ]
  assert_contains "$output" "UNCOVERED: src/mod_b/y.py"
}

@test "coverage report does not crash on a malformed (NUL-byte) declared path" {
  _seed_project_with_coverage "src/mod_a"
  printf '# Shadow Unit Overview\n- doc_role: unit_overview\n- source_of_truth_paths: src/a\000b\n- last_updated: 2026-01-01T00:00:00Z\n' \
    > "$DOCS_ROOT/shadow/apps/app-a/malformed.md"
  run COVERAGE --project-root "$TEST_PROJECT" --changed-file src/mod_b/y.py
  # Must run to completion (header printed), not abort with a traceback.
  [ "$status" -eq 0 ]
  assert_contains "$output" "# Shadow Coverage Report"
}

@test "coverage report scopes to project_root and ignores a sibling subproject change" {
  git -C "$TEST_WORKSPACE" init -q
  git -C "$TEST_WORKSPACE" config user.email t@example.com
  git -C "$TEST_WORKSPACE" config user.name t
  mkdir -p "$TEST_WORKSPACE/api/src" "$TEST_WORKSPACE/api/docs/shadow/apps/a" "$TEST_WORKSPACE/other/src"
  printf 'a=1\n' > "$TEST_WORKSPACE/api/src/x.py"
  printf 'o=1\n' > "$TEST_WORKSPACE/other/src/z.py"
  cat > "$TEST_WORKSPACE/api/docs/shadow/apps/a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths: src/x.py
- last_updated: 2026-01-01T00:00:00Z
EOF
  git -C "$TEST_WORKSPACE" add -A
  git -C "$TEST_WORKSPACE" commit -qm init
  printf 'o=2\n' > "$TEST_WORKSPACE/other/src/z.py"
  # Coverage for the api subproject must not consider the sibling 'other' change,
  # and must not leak an absolute path.
  run COVERAGE --project-root "$TEST_WORKSPACE/api"
  [ "$status" -eq 0 ]
  assert_contains "$output" "changed_source_files: 0"
  refute_contains "$output" "/other/"
}
