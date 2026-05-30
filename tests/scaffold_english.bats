#!/usr/bin/env bats

load codeguide_helper

@test "init_docs_scaffold uses project docs root directly" {
  run test -d "$DOCS_ROOT/task"
  [ "$status" -eq 0 ]
  run test -d "$DOCS_ROOT/shadow"
  [ "$status" -eq 0 ]
  run test -d "$DOCS_ROOT/orchestration/_templates"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/orchestration/_templates/ORCH.md"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/orchestration/_templates/prompt.md"
  [ "$status" -eq 0 ]
  run test ! -d "$DOCS_ROOT/orchestration/external-cli"
  [ "$status" -eq 0 ]
  run test ! -d "$DOCS_ROOT/repo"
  [ "$status" -eq 0 ]
  run test ! -d "$DOCS_ROOT/repos"
  [ "$status" -eq 0 ]
}

@test "init_docs_scaffold resolves git subdir to project docs root" {
  local workspace
  local proj
  local app_dir
  local docs_root
  local expected_docs_root
  workspace="$(mktemp -d)"
  proj="$workspace/wall"
  app_dir="$proj/backend"
  mkdir -p "$app_dir"
  git -C "$proj" init >/dev/null 2>&1

  "$INIT_SCAFFOLD" "$app_dir"
  docs_root="$(docs_root_for_project "$app_dir")"
  expected_docs_root="$(cd "$proj" && pwd -P)/docs"

  [ "$docs_root" = "$expected_docs_root" ]
  run test -d "$proj/docs/task"
  [ "$status" -eq 0 ]
  run test -d "$proj/docs/shadow"
  [ "$status" -eq 0 ]
  run test ! -e "$workspace/docs"
  [ "$status" -eq 0 ]

  rm -rf "$workspace"
}

@test "init_docs_scaffold creates shadow graph scaffold files" {
  run test -f "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/shadow/_global.md"
  [ "$status" -eq 0 ]

  run grep "^- doc_role: router" "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
  run grep "^- read_path: project-shadow.md -> <bucket>/_index.md -> <bucket>/<unit>/overview.md -> concern leaf" "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
  run grep "^- bucket_links: apps/_index.md, services/_index.md, packages/_index.md, infra/_index.md, data/_index.md" "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
  run grep "^- global_doc: _global.md" "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]

  local bucket
  for bucket in apps services packages infra data; do
    run test -f "$DOCS_ROOT/shadow/$bucket/_index.md"
    [ "$status" -eq 0 ]
    run grep "^- doc_role: bucket_index" "$DOCS_ROOT/shadow/$bucket/_index.md"
    [ "$status" -eq 0 ]
    run grep "^- bucket: $bucket" "$DOCS_ROOT/shadow/$bucket/_index.md"
    [ "$status" -eq 0 ]
    run grep "^- no units detected yet" "$DOCS_ROOT/shadow/$bucket/_index.md"
    [ "$status" -eq 0 ]
    run awk '/^## Units$/{flag=1; next} flag && /^- /{print}' "$DOCS_ROOT/shadow/$bucket/_index.md"
    [ "$status" -eq 0 ]
    [ "$output" = "- no units detected yet" ]
  done
}

@test "init_docs_scaffold creates shadow policy scaffold files" {
  run test -f "$DOCS_ROOT/policy/shadow-validator-catalog.md"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/policy/shadow-regex-patterns.md"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/policy/shadow-rule-registry.md"
  [ "$status" -eq 0 ]

  run grep "^- catalog_id: shadow-validator-catalog" "$DOCS_ROOT/policy/shadow-validator-catalog.md"
  [ "$status" -eq 0 ]
  run grep "^- template_linked_task: TASK-shadow-effect-map-01" "$DOCS_ROOT/policy/shadow-validator-catalog.md"
  [ "$status" -eq 0 ]
  run grep "^- registry_id: shadow-regex-patterns" "$DOCS_ROOT/policy/shadow-regex-patterns.md"
  [ "$status" -eq 0 ]
  run grep "^- template_linked_decision: decision-shadow-regex-standard-01" "$DOCS_ROOT/policy/shadow-regex-patterns.md"
  [ "$status" -eq 0 ]
  run grep "^- registry_id: shadow-rule-registry" "$DOCS_ROOT/policy/shadow-rule-registry.md"
  [ "$status" -eq 0 ]
  run grep "^- template_linked_decisions: decision-shadow-practical-contract-01, decision-shadow-validator-taxonomy-01, decision-shadow-regex-standard-01" "$DOCS_ROOT/policy/shadow-rule-registry.md"
  [ "$status" -eq 0 ]
}

@test "init_docs_scaffold fallback policy templates validate in strict mode" {
  local package_root="$TEST_WORKSPACE/pkg/codeguide"
  local fallback_project="$TEST_WORKSPACE/fallback/repo"

  mkdir -p "$package_root/scripts" "$fallback_project"
  cp "$INIT_SCAFFOLD" "$package_root/scripts/init_docs_scaffold.sh"
  cp "$SCRIPTS_DIR/codeguide_paths.sh" "$package_root/scripts/codeguide_paths.sh"
  cp "$SCRIPTS_DIR/codeguide_paths.py" "$package_root/scripts/codeguide_paths.py"
  chmod +x "$package_root/scripts/init_docs_scaffold.sh"

  "$package_root/scripts/init_docs_scaffold.sh" "$fallback_project"

  run "$VALIDATE" "$fallback_project" --mode strict
  [ "$status" -eq 0 ]
}

@test "check_english_docs passes for curated codeguide markdown" {
  run "$CHECK_ENGLISH_DOCS" "$(cd "$SCRIPTS_DIR/.." && pwd)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"English-only"* ]]
}

@test "check_english_docs rejects fenced code blocks in structural indexes" {
  local workspace
  workspace="$(mktemp -d)"
  mkdir -p "$workspace/references/backend"

  cat > "$workspace/references/backend/_index.md" <<'EOF'
# Backend Index

```text
no fenced blocks in indexes
```
EOF

  run "$CHECK_ENGLISH_DOCS" "$workspace"
  [ "$status" -ne 0 ]
  [[ "$output" == *"fenced code block is not allowed in structural index files"* ]]
}

@test "check_english_docs requires explicit md pointers in index entries" {
  local workspace
  workspace="$(mktemp -d)"
  mkdir -p "$workspace/references/backend"

  cat > "$workspace/references/backend/_index.md" <<'EOF'
# Backend Index

- Java / Spring Boot implementation patterns: missing pointer
EOF

  run "$CHECK_ENGLISH_DOCS" "$workspace"
  [ "$status" -ne 0 ]
  [[ "$output" == *"index entry must include a backtick-wrapped .md pointer"* ]]
}

@test "check_english_docs detects indented star index entries without md pointers" {
  local workspace
  workspace="$(mktemp -d)"
  mkdir -p "$workspace/references/backend"

  cat > "$workspace/references/backend/_index.md" <<'EOF'
# Backend Index

  * Java / Spring Boot implementation patterns: missing pointer
EOF

  run "$CHECK_ENGLISH_DOCS" "$workspace"
  [ "$status" -ne 0 ]
  [[ "$output" == *"index entry must include a backtick-wrapped .md pointer"* ]]
}

@test "check_english_docs fails on Korean text outside research exclusions" {
  local workspace
  workspace="$(mktemp -d)"

  cat > "$workspace/README.md" <<'EOF'
# Example

This file is fine.
EOF

  cat > "$workspace/notes.md" <<'EOF'
# Notes

이 문장은 실패해야 합니다.
EOF

  run "$CHECK_ENGLISH_DOCS" "$workspace"
  [ "$status" -ne 0 ]
  [[ "$output" == *"notes.md"* ]]

  rm -rf "$workspace"
}

@test "check_english_docs ignores mold research docs and temp traces" {
  local workspace
  workspace="$(mktemp -d)"
  mkdir -p "$workspace/temp"

  cat > "$workspace/mold-research.md" <<'EOF'
# Research

이 문장은 연구 문서라서 무시됩니다.
EOF

  cat > "$workspace/temp/trace.md" <<'EOF'
# Trace

이 문장은 temp 경로라서 무시됩니다.
EOF

  cat > "$workspace/README.md" <<'EOF'
# Example

This file is fine.
EOF

  run "$CHECK_ENGLISH_DOCS" "$workspace"
  [ "$status" -eq 0 ]

  rm -rf "$workspace"
}

@test "init_docs_scaffold is idempotent" {
  local workspace
  local proj
  local docs_root
  workspace="$(mktemp -d)"
  proj="$workspace/repo"
  mkdir -p "$proj"
  docs_root="$(docs_root_for_project "$proj")"

  "$INIT_SCAFFOLD" "$proj"
  # Modify a file to verify it's not overwritten
  echo "custom content" >> "$docs_root/task/project-dictionary.md"

  "$INIT_SCAFFOLD" "$proj"
  # File should still have our custom content (not reset)
  run grep "custom content" "$docs_root/task/project-dictionary.md"
  [ "$status" -eq 0 ]

  rm -rf "$workspace"
}

@test "init_docs_scaffold fails on non-existent target" {
  run "$INIT_SCAFFOLD" "/tmp/nonexistent_codeguide_test_dir_$$"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "init_docs_scaffold fails when docs path is a file" {
  local workspace
  local proj
  workspace="$(mktemp -d)"
  proj="$workspace/repo"
  mkdir -p "$proj"
  touch "$proj/docs"  # create a file, not a directory

  run "$INIT_SCAFFOLD" "$proj"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a directory"* ]]

  rm -rf "$workspace"
}

@test "init_docs_scaffold shows help with --help" {
  run "$INIT_SCAFFOLD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "init_docs_scaffold creates DOC-GOVERNANCE with new sections" {
  local workspace
  local proj
  local docs_root
  workspace="$(mktemp -d)"
  proj="$workspace/repo"
  mkdir -p "$proj"
  "$INIT_SCAFFOLD" "$proj"
  docs_root="$(docs_root_for_project "$proj")"

  run grep "Data safety" "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep "Change scope" "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep "runtime-allow-list" "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep "Plan orchestration loop" "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep "Run main-thread risk preflight before sub-agents" "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]

  run test -d "$docs_root/plan"
  [ "$status" -eq 0 ]
  run test -d "$docs_root/report"
  [ "$status" -eq 0 ]
  run test -f "$docs_root/plan/PLAN-template.md"
  [ "$status" -eq 0 ]
  run test -f "$docs_root/report/LLM-REVIEW-template.md"
  [ "$status" -eq 0 ]
  run grep "review_style" "$docs_root/report/LLM-REVIEW-template.md"
  [ "$status" -eq 0 ]
  run grep "adversarial review pass" "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep 'active task omits `risk_level`' "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep "^- risk_level:$" "$docs_root/task/task-template.md"
  [ "$status" -eq 0 ]
  run grep "^- risk_level:$" "$docs_root/decisions/decision-template.md"
  [ "$status" -eq 0 ]

  rm -rf "$workspace"
}

