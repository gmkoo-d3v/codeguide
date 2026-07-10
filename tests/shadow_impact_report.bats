#!/usr/bin/env bats

load codeguide_helper

IMPACT_REPORT() {
  python3 "$SCRIPTS_DIR/shadow_impact_report.py" "$@"
}

_seed_overview_with_source() {
  # $1 = source_of_truth_paths line body (already formatted)
  mkdir -p "$TEST_PROJECT/src" "$DOCS_ROOT/shadow/apps/app-a"
  printf 'a=1\n' > "$TEST_PROJECT/src/auth.py"
  printf 'b=1\n' > "$TEST_PROJECT/src/pay.py"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<EOF
# Shadow Unit Overview

- doc_role: unit_overview
${1}
- last_updated: 2026-01-01T00:00:00Z
EOF
}

@test "impact report flags a shadow doc whose source changed but the doc was not refreshed" {
  _seed_overview_with_source "- source_of_truth_paths: src/auth.py"
  run IMPACT_REPORT --project-root "$TEST_PROJECT" --changed-file src/auth.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"need_refresh: 1"* ]]
  [[ "$output" == *"NEEDS REFRESH: docs/shadow/apps/app-a/overview.md"* ]]
  [[ "$output" == *"src/auth.py"* ]]
}

@test "impact report treats a shadow doc as ok when it changed alongside its source" {
  _seed_overview_with_source "- source_of_truth_paths: src/auth.py"
  run IMPACT_REPORT --project-root "$TEST_PROJECT" \
    --changed-file src/auth.py --changed-file docs/shadow/apps/app-a/overview.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"need_refresh: 0"* ]]
  [[ "$output" == *"ok (refreshed alongside sources): docs/shadow/apps/app-a/overview.md"* ]]
}

@test "impact report reports no impact when the changed file is unrelated" {
  _seed_overview_with_source "- source_of_truth_paths: src/auth.py"
  run IMPACT_REPORT --project-root "$TEST_PROJECT" --changed-file src/unrelated.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"impacted_shadow_docs: 0"* ]]
  [[ "$output" == *"no shadow doc declares any changed source"* ]]
}

@test "impact report shows a distinct coverage-gap line when zero shadow docs declare source_of_truth_paths" {
  mkdir -p "$TEST_PROJECT/src" "$DOCS_ROOT/shadow/apps/app-a"
  printf 'a=1\n' > "$TEST_PROJECT/src/auth.py"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- last_updated: 2026-01-01T00:00:00Z
EOF
  run IMPACT_REPORT --project-root "$TEST_PROJECT" --changed-file src/auth.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"impacted_shadow_docs: 0"* ]]
  [[ "$output" == *"no shadow doc declares any source_of_truth_paths (coverage gap; run shadow_coverage_report.py)"* ]]
  [[ "$output" != *"no shadow doc declares any changed source"* ]]
}

@test "impact report resolves the mixed inline+nested source_of_truth_paths form" {
  _seed_overview_with_source "$(printf -- '- source_of_truth_paths: src/auth.py\n  - src/pay.py')"
  # Change only the NESTED path; it must still be recognized as an impacted source.
  run IMPACT_REPORT --project-root "$TEST_PROJECT" --changed-file src/pay.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEEDS REFRESH: docs/shadow/apps/app-a/overview.md"* ]]
  [[ "$output" == *"src/pay.py"* ]]
}

@test "impact report --exit-code returns 1 when a shadow doc needs refresh" {
  _seed_overview_with_source "- source_of_truth_paths: src/auth.py"
  run IMPACT_REPORT --project-root "$TEST_PROJECT" --changed-file src/auth.py --exit-code
  [ "$status" -eq 1 ]
}

@test "impact report ignores docs under _deprecated" {
  mkdir -p "$TEST_PROJECT/src" "$DOCS_ROOT/shadow/_deprecated/apps/app-a"
  printf 'a=1\n' > "$TEST_PROJECT/src/auth.py"
  cat > "$DOCS_ROOT/shadow/_deprecated/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths: src/auth.py
- last_updated: 2026-01-01T00:00:00Z
EOF
  run IMPACT_REPORT --project-root "$TEST_PROJECT" --changed-file src/auth.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"impacted_shadow_docs: 0"* ]]
}

@test "impact report working-tree mode flags unrefreshed source changes in a git repo" {
  git -C "$TEST_PROJECT" init -q
  git -C "$TEST_PROJECT" config user.email t@example.com
  git -C "$TEST_PROJECT" config user.name t
  _seed_overview_with_source "- source_of_truth_paths: src/auth.py"
  git -C "$TEST_PROJECT" add -A
  git -C "$TEST_PROJECT" commit -qm init
  # Modify only the source in the working tree.
  printf 'a=2\n' > "$TEST_PROJECT/src/auth.py"
  run IMPACT_REPORT --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEEDS REFRESH: docs/shadow/apps/app-a/overview.md"* ]]
}

@test "impact report errors clearly when there is no git repo and no explicit change set" {
  _seed_overview_with_source "- source_of_truth_paths: src/auth.py"
  run IMPACT_REPORT --project-root "$TEST_PROJECT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not inside a git repository"* ]]
}

@test "impact report handles project_root that is a subproject below the git root" {
  # git repo at the workspace; docs/shadow live in a subproject one level down.
  git -C "$TEST_WORKSPACE" init -q
  git -C "$TEST_WORKSPACE" config user.email t@example.com
  git -C "$TEST_WORKSPACE" config user.name t
  local sub="$TEST_WORKSPACE/sub"
  mkdir -p "$sub/src" "$sub/docs/shadow/apps/app-a"
  printf 'a=1\n' > "$sub/src/auth.py"
  cat > "$sub/docs/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths: src/auth.py
- last_updated: 2026-01-01T00:00:00Z
EOF
  git -C "$TEST_WORKSPACE" add -A
  git -C "$TEST_WORKSPACE" commit -qm init
  printf 'a=2\n' > "$sub/src/auth.py"
  # project-root is the subproject; its docs/shadow and source must resolve, and the
  # git root (one level up) is used only to expand the diff paths.
  run IMPACT_REPORT --project-root "$sub"
  [ "$status" -eq 0 ]
  [[ "$output" == *"impacted_shadow_docs: 1"* ]]
  [[ "$output" == *"NEEDS REFRESH: docs/shadow/apps/app-a/overview.md"* ]]
}

@test "impact report still flags a source that was renamed away (no-renames)" {
  git -C "$TEST_PROJECT" init -q
  git -C "$TEST_PROJECT" config user.email t@example.com
  git -C "$TEST_PROJECT" config user.name t
  _seed_overview_with_source "- source_of_truth_paths: src/auth.py"
  git -C "$TEST_PROJECT" add -A
  git -C "$TEST_PROJECT" commit -qm init
  git -C "$TEST_PROJECT" mv src/auth.py src/auth_renamed.py
  run IMPACT_REPORT --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEEDS REFRESH: docs/shadow/apps/app-a/overview.md"* ]]
  [[ "$output" == *"src/auth.py"* ]]
}

@test "impact report works in a fresh repo with no commits (unborn HEAD)" {
  git -C "$TEST_PROJECT" init -q
  git -C "$TEST_PROJECT" config user.email t@example.com
  git -C "$TEST_PROJECT" config user.name t
  _seed_overview_with_source "- source_of_truth_paths: src/auth.py"
  # No commit at all; everything is untracked. Must not crash.
  run IMPACT_REPORT --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"impacted_shadow_docs: 1"* ]]
}

@test "impact report rejects combining --range with --changed-file" {
  _seed_overview_with_source "- source_of_truth_paths: src/auth.py"
  run IMPACT_REPORT --project-root "$TEST_PROJECT" --range HEAD --changed-file src/auth.py
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

@test "impact report --range mode reports impact across a commit range" {
  git -C "$TEST_PROJECT" init -q
  git -C "$TEST_PROJECT" config user.email t@example.com
  git -C "$TEST_PROJECT" config user.name t
  _seed_overview_with_source "- source_of_truth_paths: src/auth.py"
  git -C "$TEST_PROJECT" add -A
  git -C "$TEST_PROJECT" commit -qm init
  printf 'a=2\n' > "$TEST_PROJECT/src/auth.py"
  git -C "$TEST_PROJECT" commit -qam change-source
  run IMPACT_REPORT --project-root "$TEST_PROJECT" --range HEAD~1..HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEEDS REFRESH: docs/shadow/apps/app-a/overview.md"* ]]
}

_seed_split_root_layout() {
  # docs-only parent repo + marker-declared nested source repo
  SPLIT_PARENT="$TEST_WORKSPACE/split"
  mkdir -p "$SPLIT_PARENT/skillpkg/scripts" "$SPLIT_PARENT/docs/shadow/apps/app-a"
  printf -- "---\nname: fixture-skill\n---\n" > "$SPLIT_PARENT/skillpkg/SKILL.md"
  git -C "$SPLIT_PARENT/skillpkg" init --quiet
  printf 'a=1\n' > "$SPLIT_PARENT/skillpkg/src.py"
  git -C "$SPLIT_PARENT/skillpkg" add -A
  git -C "$SPLIT_PARENT/skillpkg" -c user.email=t@t -c user.name=t commit -qm init
  printf 'skillpkg\n' > "$SPLIT_PARENT/.codeguide-source-root"
  cat > "$SPLIT_PARENT/docs/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths: skillpkg/src.py
- last_updated: 2026-01-01T00:00:00Z
EOF
  git -C "$SPLIT_PARENT" init --quiet
  printf 'skillpkg/\n' > "$SPLIT_PARENT/.gitignore"
  git -C "$SPLIT_PARENT" add -A
  git -C "$SPLIT_PARENT" -c user.email=t@t -c user.name=t commit -qm init
  printf 'a=2\n' > "$SPLIT_PARENT/skillpkg/src.py"
}

@test "impact report split-root: docs-repo working-tree refresh is detected" {
  _seed_split_root_layout
  printf -- '- note: refreshed for src change\n' >> "$SPLIT_PARENT/docs/shadow/apps/app-a/overview.md"

  run IMPACT_REPORT --project-root "$SPLIT_PARENT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"need_refresh: 0"* ]]
  [[ "$output" == *"ok (refreshed alongside sources)"* ]]
}

@test "impact report split-root: untouched shadow doc still needs refresh" {
  _seed_split_root_layout

  run IMPACT_REPORT --project-root "$SPLIT_PARENT" --exit-code
  [ "$status" -eq 1 ]
  [[ "$output" == *"need_refresh: 1"* ]]
  [[ "$output" == *"NEEDS REFRESH"* ]]
}

_seed_split_root_layout_untracked() {
  # split-root layout whose docs parent is NOT a git repository
  SPLIT_PARENT="$TEST_WORKSPACE/split-untracked"
  mkdir -p "$SPLIT_PARENT/skillpkg/scripts" "$SPLIT_PARENT/docs/shadow/apps/app-a"
  printf -- "---\nname: fixture-skill\n---\n" > "$SPLIT_PARENT/skillpkg/SKILL.md"
  git -C "$SPLIT_PARENT/skillpkg" init --quiet
  printf 'a=1\n' > "$SPLIT_PARENT/skillpkg/src.py"
  git -C "$SPLIT_PARENT/skillpkg" add -A
  git -C "$SPLIT_PARENT/skillpkg" -c user.email=t@t -c user.name=t commit -qm init
  printf 'skillpkg\n' > "$SPLIT_PARENT/.codeguide-source-root"
  cat > "$SPLIT_PARENT/docs/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths: skillpkg/src.py
- last_updated: 2026-01-01T00:00:00Z
EOF
  printf 'a=2\n' > "$SPLIT_PARENT/skillpkg/src.py"
}

@test "impact report split-root without a docs repo reports unknown instead of false NEEDS REFRESH" {
  _seed_split_root_layout_untracked
  printf -- '- note: refreshed for src change\n' >> "$SPLIT_PARENT/docs/shadow/apps/app-a/overview.md"

  run IMPACT_REPORT --project-root "$SPLIT_PARENT" --exit-code
  [ "$status" -eq 0 ]
  [[ "$output" == *"refresh_unknown: 1"* ]]
  [[ "$output" == *"refresh state unknown"* ]]
  [[ "$output" == *"refresh detection is unavailable"* ]]
  [[ "$output" != *"NEEDS REFRESH"* ]]
}

@test "impact report split-root without a docs repo keeps --changed-file refresh detection" {
  _seed_split_root_layout_untracked

  run IMPACT_REPORT --project-root "$SPLIT_PARENT" \
    --changed-file skillpkg/src.py --changed-file docs/shadow/apps/app-a/overview.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"need_refresh: 0"* ]]
  [[ "$output" == *"ok (refreshed alongside sources)"* ]]
}
