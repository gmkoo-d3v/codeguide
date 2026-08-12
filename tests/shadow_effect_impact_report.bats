#!/usr/bin/env bats

load codeguide_helper

IMPACT_REPORT() {
  python3 "$SCRIPTS_DIR/shadow_effect_impact_report.py" "$@"
}

_seed_effect_doc() {
  # $1 = doc path relative to DOCS_ROOT (e.g. shadow/effectmap.md)
  # $2 = lifecycle
  # $3 = anchor_file (project-root relative, e.g. src/UserService.java)
  local doc_path="$1"
  local lifecycle="$2"
  local anchor_file="$3"
  mkdir -p "$DOCS_ROOT/$(dirname "$doc_path")"
  cat > "$DOCS_ROOT/$doc_path" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-fx-101 begin -->
## SE-fx-101

- record_id: SE-fx-101
- record_type: effect_map_entry
- lifecycle: ${lifecycle}
- effect_type: cache_evict
- statement: fixture effect record for the impact reporter
- anchor_file: ${anchor_file}
- anchor_symbol: UserRepository.save

<!-- shadow-effect-record:SE-fx-101 end -->
EOF
}

_seed_anchor() {
  # $1 = project-root relative path of the anchor file (content is irrelevant)
  mkdir -p "$TEST_PROJECT/$(dirname "$1")"
  printf 'class Fixture {}\n' > "$TEST_PROJECT/$1"
}

@test "effect impact report flags a confirmed anchor in the change set" {
  _seed_effect_doc "shadow/effectmap.md" "confirmed" "src/UserService.java"
  _seed_anchor "src/UserService.java"
  run IMPACT_REPORT --project-root "$TEST_PROJECT" --changed-file src/UserService.java
  [ "$status" -eq 0 ]
  assert_contains "$output" "re-verify: docs/shadow/effectmap.md record SE-fx-101 (lifecycle confirmed) — anchor src/UserService.java is in the change set; human or deterministic evidence decision required"
  assert_contains "$output" "summary: 1 re-verify, 0 anchor-missing"
}

@test "effect impact report does not flag non-confirmed anchors" {
  _seed_effect_doc "shadow/effectmap.md" "unknown" "src/UserService.java"
  _seed_anchor "src/UserService.java"
  run IMPACT_REPORT --project-root "$TEST_PROJECT" --changed-file src/UserService.java
  [ "$status" -eq 0 ]
  refute_contains "$output" "re-verify:"
  assert_contains "$output" "summary: 0 re-verify, 0 anchor-missing"
}

@test "effect impact report does not flag when a changed file is not an anchor" {
  _seed_effect_doc "shadow/effectmap.md" "confirmed" "src/UserService.java"
  _seed_anchor "src/UserService.java"
  _seed_anchor "src/Other.java"
  run IMPACT_REPORT --project-root "$TEST_PROJECT" --changed-file src/Other.java
  [ "$status" -eq 0 ]
  refute_contains "$output" "re-verify:"
  assert_contains "$output" "summary: 0 re-verify, 0 anchor-missing"
}

@test "effect impact report warns when an effect anchor file does not exist" {
  _seed_effect_doc "shadow/effectmap.md" "unknown" "src/Gone.java"
  _seed_anchor "src/Other.java"
  run IMPACT_REPORT --project-root "$TEST_PROJECT" --changed-file src/Other.java
  [ "$status" -eq 0 ]
  assert_contains "$output" "anchor-missing: docs/shadow/effectmap.md record SE-fx-101 (lifecycle unknown) — anchor src/Gone.java does not exist"
  assert_contains "$output" "(lifecycle unknown)"
  refute_contains "$output" "re-verify:"
  assert_contains "$output" "summary: 0 re-verify, 1 anchor-missing"
}

@test "effect impact report never auto-decides invalidation" {
  _seed_effect_doc "shadow/effectmap.md" "confirmed" "src/UserService.java"
  _seed_anchor "src/UserService.java"
  run IMPACT_REPORT --project-root "$TEST_PROJECT" --changed-file src/UserService.java --exit-code
  [ "$status" -eq 1 ]
  refute_contains "$output" "invalidat"
  assert_contains "$output" "re-verify: docs/shadow/effectmap.md record SE-fx-101 (lifecycle confirmed)"
}

@test "effect impact report is empty for a doc with no records" {
  mkdir -p "$DOCS_ROOT/shadow"
  cat > "$DOCS_ROOT/shadow/effectmap.md" <<'EOF'
# Effects

- doc_role: effect_map
EOF
  run IMPACT_REPORT --project-root "$TEST_PROJECT" --changed-file src/Whatever.java
  [ "$status" -eq 0 ]
  assert_contains "$output" "# Shadow Effect Impact Report"
  refute_contains "$output" "re-verify:"
  refute_contains "$output" "anchor-missing:"
}

@test "effect impact report finds effect_map docs across the shadow tree" {
  _seed_effect_doc "shadow/packages/foo/effectmap.md" "confirmed" "src/UserService.java"
  _seed_anchor "src/UserService.java"
  run IMPACT_REPORT --project-root "$TEST_PROJECT" --changed-file src/UserService.java
  [ "$status" -eq 0 ]
  assert_contains "$output" "re-verify: docs/shadow/packages/foo/effectmap.md record SE-fx-101"
  assert_contains "$output" "docs/shadow/packages/foo/effectmap.md"
}
