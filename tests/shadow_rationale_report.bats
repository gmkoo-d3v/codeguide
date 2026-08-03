#!/usr/bin/env bats

load codeguide_helper

RATIONALE() {
  python3 "$SCRIPTS_DIR/shadow_rationale_report.py" "$@"
}

_capsule() {
  # $1 = decision id, $2 = status
  cat > "$DOCS_ROOT/decisions/decision-${1}.md" <<EOF
# decision-${1}

- decision_id: ${1}
- title: fixture
- date: 2026-08-01
- scope_type: task
- status: ${2}
- chosen_by: user
- last_updated: 2026-08-01T00:00:00Z
EOF
}

_overview() {
  # $1 = unit id, $2 = linked_decisions value
  mkdir -p "$DOCS_ROOT/shadow/apps/${1}"
  {
    printf '# Shadow Unit Overview\n\n- doc_role: unit_overview\n- home_bucket: apps\n'
    printf -- '- linked_decisions: %s\n' "$2"
    printf -- '- last_updated: 2026-08-01T00:00:00Z\n'
  } > "$DOCS_ROOT/shadow/apps/${1}/overview.md"
}

@test "rationale report is empty but valid on a fresh scaffold" {
  run RATIONALE --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow_docs_with_rationale: 0"
  assert_contains "$output" "problems: 0"
}

@test "rationale report lists both directions of a resolved edge" {
  _capsule report-fwd-01 accepted
  _overview app-a "docs/decisions/decision-report-fwd-01.md"
  run RATIONALE --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow_docs_with_rationale: 1"
  assert_contains "$output" "decisions_cited: 1"
  assert_contains "$output" "docs/shadow/apps/app-a/overview.md: docs/decisions/decision-report-fwd-01.md [accepted]"
  assert_contains "$output" "docs/decisions/decision-report-fwd-01.md: docs/shadow/apps/app-a/overview.md"
}

@test "rationale report aggregates several shadow docs citing one decision" {
  _capsule report-shared-01 accepted
  _overview app-a "docs/decisions/decision-report-shared-01.md"
  _overview app-b "docs/decisions/decision-report-shared-01.md"
  run RATIONALE --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "docs/decisions/decision-report-shared-01.md: docs/shadow/apps/app-a/overview.md, docs/shadow/apps/app-b/overview.md"
}

@test "rationale report lists accepted decisions that no shadow doc cites" {
  _capsule report-uncited-01 accepted
  _capsule report-proposed-01 proposed
  run RATIONALE --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "accepted_decisions_uncited: 1"
  assert_contains "$output" "- docs/decisions/decision-report-uncited-01.md"
  # A proposed capsule is not a coverage gap: it is not settled rationale yet.
  refute_contains "$output" "decision-report-proposed-01.md"
}

@test "rationale report surfaces dangling, malformed, index, and duplicate entries" {
  _capsule report-dup-01 accepted
  _overview app-a "docs/decisions/decision-missing-01.md, bare-id-01, docs/decisions/decision-index.md"
  _overview app-b "docs/decisions/decision-report-dup-01.md, docs/decisions/decision-report-dup-01.md"
  run RATIONALE --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "docs/decisions/decision-missing-01.md does not resolve"
  assert_contains "$output" "bare-id-01 is not a repo-relative docs/decisions/decision-<id>.md path"
  assert_contains "$output" "docs/decisions/decision-index.md is not a decision capsule (index/template carry no rationale)"
  assert_contains "$output" "duplicate entry docs/decisions/decision-report-dup-01.md"
}

@test "rationale report flags rationale declared on a non-carrier doc_role" {
  _capsule report-role-01 accepted
  cat > "$DOCS_ROOT/shadow/_global.md" <<'EOF'
# Shadow Global

- doc_role: global
- linked_decisions: docs/decisions/decision-report-role-01.md
- last_updated: 2026-08-01T00:00:00Z
EOF
  run RATIONALE --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "linked_decisions on doc_role=global"
}

@test "rationale report ignores fenced examples and the _deprecated tree" {
  _capsule report-fence-01 accepted
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a" "$DOCS_ROOT/shadow/_deprecated/apps/app-z"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- last_updated: 2026-08-01T00:00:00Z

```
- linked_decisions: docs/decisions/decision-report-fence-01.md
```
EOF
  cat > "$DOCS_ROOT/shadow/_deprecated/apps/app-z/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- linked_decisions: docs/decisions/decision-report-fence-01.md
- last_updated: 2026-08-01T00:00:00Z
EOF
  run RATIONALE --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow_docs_with_rationale: 0"
  assert_contains "$output" "problems: 0"
}

@test "rationale report resolves the git root when given a subproject path" {
  git -C "$TEST_PROJECT" init -q
  git -C "$TEST_PROJECT" config user.email t@example.com
  git -C "$TEST_PROJECT" config user.name t
  mkdir -p "$TEST_PROJECT/sub/src"
  _capsule report-subroot-01 accepted
  _overview app-a "docs/decisions/decision-report-subroot-01.md"
  run RATIONALE --project-root "$TEST_PROJECT/sub"
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow_docs_with_rationale: 1"
  refute_contains "$output" "no shadow dir"
}

@test "rationale report exits 2 on a usage error and 0 with findings" {
  run RATIONALE
  [ "$status" -eq 2 ]

  _overview app-a "docs/decisions/decision-missing-01.md"
  run RATIONALE --project-root "$TEST_PROJECT"
  # Findings never change the exit code: the validator owns the pass/fail opinion.
  [ "$status" -eq 0 ]
  assert_contains "$output" "problems: 1"
}

@test "rationale report writes nothing: no new bytecode cache and no doc mutation" {
  _capsule report-readonly-01 accepted
  _overview app-a "docs/decisions/decision-report-readonly-01.md"
  local docs_before cache_before
  docs_before="$(shasum "$DOCS_ROOT/shadow/apps/app-a/overview.md" "$DOCS_ROOT/decisions/decision-report-readonly-01.md")"
  # Snapshot the WHOLE cache dir, not just this script's .pyc: a __main__ script
  # never produces one, so watching only shadow_rationale_report.*.pyc would pass
  # even with sys.dont_write_bytecode deleted -- importing codeguide_paths is what
  # would actually write. Compare the inventory instead.
  cache_before="$(ls -1 "$SCRIPTS_DIR/__pycache__" 2>/dev/null | sort)"
  run RATIONALE --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [ "$(ls -1 "$SCRIPTS_DIR/__pycache__" 2>/dev/null | sort)" = "$cache_before" ]
  [ "$(shasum "$DOCS_ROOT/shadow/apps/app-a/overview.md" "$DOCS_ROOT/decisions/decision-report-readonly-01.md")" = "$docs_before" ]
}

@test "rationale report prints all five sections even when empty and is byte-stable" {
  run RATIONALE --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "## Shadow doc -> decisions"
  assert_contains "$output" "## Decision -> citing shadow docs"
  assert_contains "$output" "## Accepted decisions no shadow doc cites"
  assert_contains "$output" "## Problems"
  assert_contains "$output" "## Notes"

  _capsule report-stable-01 accepted
  _capsule report-stable-02 proposed
  _overview app-a "docs/decisions/decision-report-stable-01.md, docs/decisions/decision-report-stable-02.md"
  local first second
  first="$(RATIONALE --project-root "$TEST_PROJECT")"
  second="$(RATIONALE --project-root "$TEST_PROJECT")"
  [ "$first" = "$second" ]
  assert_contains "$first" "notes: 1"
  assert_contains "$first" "is only proposed"
}

@test "rationale report exits 2 on a nonexistent project root" {
  run RATIONALE --project-root "$TEST_WORKSPACE/not-a-real-root"
  [ "$status" -eq 2 ]
}

@test "rationale report surfaces the nested-bullet form while a tilde-fenced example stays silent" {
  _capsule report-nested-01 accepted
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a" "$DOCS_ROOT/shadow/apps/app-b"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- linked_decisions:
  - docs/decisions/decision-report-nested-01.md
- last_updated: 2026-08-01T00:00:00Z
EOF
  cat > "$DOCS_ROOT/shadow/apps/app-b/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- last_updated: 2026-08-01T00:00:00Z

~~~
- linked_decisions:
  - docs/decisions/decision-report-nested-01.md
~~~
EOF
  run RATIONALE --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "docs/shadow/apps/app-a/overview.md: must be an inline comma list, not nested bullets"
  refute_contains "$output" "app-b"
}

@test "rationale report does not close a backtick fence on a tilde marker" {
  # The divergence that the task exists to end. The report used
  # to toggle fence state on ANY marker, so `~~~` closed the block and the closing
  # backtick reopened one that ran to end of file: the example leaked out and the
  # real field below was swallowed. Both errors are asserted here.
  _capsule report-mixed-01 accepted
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps

```
- linked_decisions: docs/decisions/decision-nowhere-99.md
~~~
```

- linked_decisions: docs/decisions/decision-report-mixed-01.md
- last_updated: 2026-08-01T00:00:00Z
EOF
  run RATIONALE --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  refute_contains "$output" "decision-nowhere-99.md"
  assert_contains "$output" "shadow_docs_with_rationale: 1"
  assert_contains "$output" "docs/decisions/decision-report-mixed-01.md [accepted]"
  assert_contains "$output" "problems: 0"
}

@test "a fence boundary breaks the linked_decisions header-to-bullet binding" {
  # content_lines() drops fenced lines but hides that a block happened, which would
  # bind an indented bullet to a header on the far side of the fence. scan() reports
  # the boundary, which is the rule check_shadow_navigation_links already applies.
  # Both directions in one test, so it cannot pass by the rule doing nothing:
  # app-a has a fence between header and bullet (must stay silent), app-b has the
  # genuine adjacent nested form (must still fire).
  _capsule report-bind-01 accepted
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a" "$DOCS_ROOT/shadow/apps/app-b"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- linked_decisions:

```
example block
```

  - docs/decisions/decision-report-bind-01.md
- last_updated: 2026-08-01T00:00:00Z
EOF
  cat > "$DOCS_ROOT/shadow/apps/app-b/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- linked_decisions:
  - docs/decisions/decision-report-bind-01.md
- last_updated: 2026-08-01T00:00:00Z
EOF
  run RATIONALE --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  refute_contains "$output" "docs/shadow/apps/app-a/overview.md: must be an inline comma list"
  assert_contains "$output" "docs/shadow/apps/app-b/overview.md: must be an inline comma list"
  assert_contains "$output" "problems: 1"
}

@test "rationale report ignores a second linked_decisions occurrence" {
  _capsule report-first-01 accepted
  _capsule report-second-01 accepted
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- linked_decisions: docs/decisions/decision-report-first-01.md
- linked_decisions: docs/decisions/decision-report-second-01.md
- last_updated: 2026-08-01T00:00:00Z
EOF
  run RATIONALE --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "decision-report-first-01.md [accepted]"
  refute_contains "$output" "decision-report-second-01.md ["
}

@test "rationale --lint emits the declared summary and tab-separated findings" {
  _capsule report-lint-01 accepted
  _overview app-a "docs/decisions/decision-report-lint-01.md, docs/decisions/decision-missing-99.md"
  run RATIONALE --project-root "$TEST_PROJECT" --lint
  [ "$status" -eq 0 ]
  # The summary record is `declared<TAB><count>`; assert the exact line.
  assert_contains "$output" "$(printf 'declared\t1')"
  assert_contains "$output" "$(printf 'dangling\tdocs/shadow/apps/app-a/overview.md\tdocs/decisions/decision-missing-99.md')"
  # --lint is the validator's input: it must never print the report headings.
  refute_contains "$output" "# Shadow Rationale Report"
}
