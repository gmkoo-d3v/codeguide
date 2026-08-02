#!/usr/bin/env bats

load codeguide_helper

NAVGRAPH() {
  python3 "$SCRIPTS_DIR/shadow_nav_graph_report.py" "$@"
}

_link_overview_in_bucket() {
  # $1 = unit id, links docs/shadow/apps/$1/overview.md into apps/_index.md
  cat >> "$DOCS_ROOT/shadow/apps/_index.md" <<EOF
- unit_id: ${1}
  - overview_doc: apps/${1}/overview.md
EOF
}

@test "nav graph report finds no orphans in a fresh scaffold" {
  run NAVGRAPH --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "router_present: yes"
  assert_contains "$output" "orphans: 0"
}

@test "nav graph report flags an overview that no bucket index links" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  printf '# o\n- doc_role: unit_overview\n- home_bucket: apps\n' > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  run NAVGRAPH --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "orphans: 1"
  assert_contains "$output" "ORPHAN: docs/shadow/apps/app-a/overview.md"
}

@test "nav graph report treats an overview linked from its bucket index as reachable" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  printf '# o\n- doc_role: unit_overview\n- home_bucket: apps\n' > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  _link_overview_in_bucket app-a
  run NAVGRAPH --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "orphans: 0"
  assert_contains "$output" "apps/app-a/overview.md: 2 hops"
}

@test "nav graph report reaches a concern leaf via next_docs but orphans an unlinked one" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  printf '# o\n- doc_role: unit_overview\n- home_bucket: apps\n- next_docs: apps/app-a/auth.md\n' \
    > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  printf '# c\n- doc_role: concern_leaf\n- concern_id: auth\n' > "$DOCS_ROOT/shadow/apps/app-a/auth.md"
  printf '# c\n- doc_role: concern_leaf\n- concern_id: lonely\n' > "$DOCS_ROOT/shadow/apps/app-a/lonely.md"
  _link_overview_in_bucket app-a
  run NAVGRAPH --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "apps/app-a/auth.md: 3 hops"
  assert_contains "$output" "ORPHAN: docs/shadow/apps/app-a/lonely.md"
  refute_contains "$output" "ORPHAN: docs/shadow/apps/app-a/auth.md"
}

@test "nav graph report --exit-code returns 1 when an orphan exists" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  printf '# o\n- doc_role: unit_overview\n- home_bucket: apps\n' > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  run NAVGRAPH --project-root "$TEST_PROJECT" --exit-code
  [ "$status" -eq 1 ]
}

@test "nav graph report does not orphan an unreachable side-path doc (effect_map)" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/effects.md" <<'EOF'
# Shadow Effects

- doc_role: effect_map
- generated_by: shadow_effect_writer.py
EOF
  run NAVGRAPH --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  # effect_map is an intentional side-path, not orphan-eligible.
  assert_contains "$output" "orphans: 0"
}

@test "nav graph report ignores docs under _deprecated" {
  mkdir -p "$DOCS_ROOT/shadow/_deprecated/apps/app-a"
  printf '# o\n- doc_role: unit_overview\n- home_bucket: apps\n' \
    > "$DOCS_ROOT/shadow/_deprecated/apps/app-a/overview.md"
  run NAVGRAPH --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "orphans: 0"
}

@test "nav graph report reports a missing router instead of crashing" {
  rm -f "$DOCS_ROOT/shadow/project-shadow.md"
  run NAVGRAPH --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "router_present: no"
  assert_contains "$output" "router is missing"
}

@test "nav graph report does not attach a post-fence bullet to a nav field (fence reset)" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  _link_overview_in_bucket app-a
  # next_docs header, a fenced example, then an unrelated deeper bullet after the fence.
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- next_docs:
```
example:
  - notes.md
```
  - ghost.md
EOF
  printf '# c\n- doc_role: concern_leaf\n- concern_id: ghost\n' > "$DOCS_ROOT/shadow/apps/app-a/ghost.md"
  run NAVGRAPH --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  # ghost.md must NOT be treated as a next_docs target, so it stays an orphan.
  assert_contains "$output" "ORPHAN: docs/shadow/apps/app-a/ghost.md"
}

@test "nav graph report resolves the git root when given a subproject path" {
  git -C "$TEST_PROJECT" init -q
  git -C "$TEST_PROJECT" config user.email t@example.com
  git -C "$TEST_PROJECT" config user.name t
  mkdir -p "$TEST_PROJECT/sub/src"
  printf 'x=1\n' > "$TEST_PROJECT/sub/src/a.py"
  # docs/shadow is at the git root; passing the subdir must climb, not no-op.
  run NAVGRAPH --project-root "$TEST_PROJECT/sub"
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow_docs: 7"
  refute_contains "$output" "no shadow dir"
}

@test "nav graph report reaches a carrier through a redirect_shim canonical_path" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat >> "$DOCS_ROOT/shadow/apps/_index.md" <<'EOF'
- unit_id: app-a
  - overview_doc: apps/app-a/legacy.md
EOF
  cat > "$DOCS_ROOT/shadow/apps/app-a/legacy.md" <<'EOF'
# Shadow Redirect

- doc_role: redirect_shim
- canonical_path: apps/app-a/overview.md
- status: redirected
EOF
  printf '# o\n- doc_role: unit_overview\n- home_bucket: apps\n' > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  run NAVGRAPH --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "orphans: 0"
}

@test "nav graph report surfaces a doc with an unrecognized doc_role as unclassified" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  printf '# o\n- doc_role: unit_overivew\n- home_bucket: apps\n' \
    > "$DOCS_ROOT/shadow/apps/app-a/typo.md"
  run NAVGRAPH --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "unclassified: 1"
  assert_contains "$output" "UNCLASSIFIED: docs/shadow/apps/app-a/typo.md"
}

@test "nav graph report orphans a bucket index the router does not link" {
  perl -0pi -e 's{^- bucket_links:.*$}{- bucket_links: services/_index.md, packages/_index.md, infra/_index.md, data/_index.md}m' \
    "$DOCS_ROOT/shadow/project-shadow.md"
  run NAVGRAPH --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "ORPHAN: docs/shadow/apps/_index.md"
}
