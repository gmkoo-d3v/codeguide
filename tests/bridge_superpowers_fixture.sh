#!/usr/bin/env bash
# Fixture verification harness for codeguide/scripts/bridge_superpowers.sh
#
#
# Standalone bash (NOT bats): it must build its scratch roots INSIDE the
# project, unlike the bats suite's `mktemp -d` helper. All scratch state lives
# under <project>/.bridge-fixtures/ and is removed on full success (kept on
# failure for inspection). The harness never writes outside the project.
#
# Isolation contract: each fixture root is its own git repository (`git init`
# inside it), so doc_garden.sh's root resolution
# (codeguide_resolve_project_root -> `git rev-parse --show-toplevel`) stops at
# the fixture and NEVER ascends to the real codeguide repo — otherwise the
# fixture run would register its task in the REAL docs/task/task-index.md.
#
# Usage: bash bridge_superpowers_fixture.sh [bridge-script-path]
#   The optional first argument points the harness at a bridge script copy
#   (default: the real codeguide/scripts/bridge_superpowers.sh).

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURES_ROOT="$PROJECT_DIR/.bridge-fixtures"

BRIDGE_SCRIPT="${1:-$PROJECT_DIR/codeguide/scripts/bridge_superpowers.sh}"
if [[ "$BRIDGE_SCRIPT" != /* && -n "${1:-}" ]]; then
  BRIDGE_SCRIPT="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")"
fi

if [[ ! -f "$BRIDGE_SCRIPT" ]]; then
  echo "Error: bridge script not found at '$BRIDGE_SCRIPT'" >&2
  exit 1
fi
if ! bash -n "$BRIDGE_SCRIPT"; then
  echo "Error: bridge script '$BRIDGE_SCRIPT' fails bash -n" >&2
  exit 1
fi

# Directory beside the bridge script under test; used to give fixture bin/
# copies the shared fence-aware reader adapter (F8 post-condition).
BRIDGE_SCRIPT_DIR="$(cd "$(dirname "$BRIDGE_SCRIPT")" && pwd)"

echo "bridge script under test: $BRIDGE_SCRIPT"

# ---------------------------------------------------------------- helpers ---

# Assert helpers in the style of codeguide/tests/codeguide_helper.bash. An
# empty needle asserts nothing and is rejected rather than misread as a pass.
assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ -z "$needle" ]]; then
    printf 'assert_contains called with an empty needle (asserts nothing)\n' >&2
    return 1
  fi
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'assert_contains failed\n  expected to find: %s\n  in: %s\n' "$needle" "$haystack" >&2
    return 1
  fi
}

refute_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ -z "$needle" ]]; then
    printf 'refute_contains called with an empty needle (asserts nothing)\n' >&2
    return 1
  fi
  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'refute_contains failed\n  expected NOT to find: %s\n  in: %s\n' "$needle" "$haystack" >&2
    return 1
  fi
}

assert_equal() {
  local actual="$1"
  local expected="$2"
  if [[ "$actual" != "$expected" ]]; then
    printf 'assert_equal failed\n  expected: %s\n  actual:   %s\n' "$expected" "$actual" >&2
    return 1
  fi
}

file_sha256() {
  python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
}

# --- framework: every scenario function runs all its assertions and returns
# --- non-zero if any of them failed; run_scenario prints PASS/FAIL + summary.

PASS_COUNT=0
FAIL_COUNT=0

run_scenario() {
  local name="$1"
  shift
  local output
  local rc
  output="$("$@" 2>&1)"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "PASS: $name"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "FAIL: $name"
    printf '%s\n' "$output" | sed 's/^/    /'
  fi
}

# --- fixture helpers ---

new_fixture() {
  local case_name="$1"
  local root="$FIXTURES_ROOT/$case_name"
  rm -rf "$root"
  mkdir -p "$root"
  git -C "$root" init -q || { echo "  git init failed for $root" >&2; return 1; }
  echo "$root"
}

# Isolation preflight: the fixture must be its own git toplevel. If this
# fails, every scenario below would write into the REAL codeguide repo.
assert_fixture_isolated() {
  local root="$1"
  local top
  local resolved
  top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)"
  resolved="$(cd "$root" && pwd -P)"
  if [[ "$top" != "$resolved" ]]; then
    echo "  fixture '$root' is not its own git toplevel (resolves to '$top'); aborting scenario" >&2
    return 1
  fi
}

# Run the bridge script against a fixture root; leaves $root/<tag>.stdout and
# $root/<tag>.stderr for assertions; sets RC_LAST to the bridge exit code.
RC_LAST=0
run_promote() {
  local script="$1"
  local root="$2"
  local task_id="$3"
  local draft="$4"
  local tag="${5:-run}"
  (cd "$root" && bash "$script" "$root" promote --draft "$draft" --task-id "$task_id" --risk-level medium) \
    > "$root/${tag}.stdout" 2> "$root/${tag}.stderr"
  RC_LAST=$?
}

# A ledger row for the task must not exist anywhere in the fixture docs.
assert_no_ledger_row() {
  local root="$1"
  local task_id="$2"
  local index="$root/docs/task/task-index.md"
  if [[ -f "$index" ]]; then
    refute_contains "$(cat "$index")" "TASK-${task_id} |" || return 1
  fi
}

make_draft() {
  local root="$1"
  local plan_name="$2"
  mkdir -p "$root/.superpowers/plans"
  printf '# %s\n\n- objective: bridge fixture scenario\n- status: planned\n' "$plan_name" \
    > "$root/.superpowers/plans/$plan_name.md"
  echo "$root/.superpowers/plans/$plan_name.md"
}

# ------------------------------------------------------------- scenarios ---

# 1. Happy-path promote: symlink created and resolving, ledger row written,
#    draft byte-identical afterwards (non-destructive).
scn1_happy_path() {
  local rc=0
  local root draft target index before_sha after_sha rel_expected

  root="$(new_fixture "01-happy-path")" || return 1
  assert_fixture_isolated "$root" || return 1
  draft="$(make_draft "$root" "PLAN-bridge-ok-01")" || return 1
  before_sha="$(file_sha256 "$draft")"

  run_promote "$BRIDGE_SCRIPT" "$root" "bridge-ok-01" "$draft" "run1"
  assert_equal "$RC_LAST" 0 || rc=1

  target="$root/docs/plan/PLAN-bridge-ok-01-v1.0.md"
  if [[ ! -L "$target" ]]; then echo "  expected symlink at '$target'" >&2; rc=1; fi
  if [[ ! -e "$target" ]]; then echo "  expected symlink to resolve: '$target'" >&2; rc=1; fi
  rel_expected="$(python3 -c "import sys, os; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$draft" "$root/docs/plan")"
  assert_equal "$(readlink "$target")" "$rel_expected" || rc=1

  index="$root/docs/task/task-index.md"
  if [[ ! -f "$index" ]]; then echo "  expected task-index at '$index'" >&2; rc=1; fi
  assert_contains "$(cat "$index")" "- TASK-bridge-ok-01 | in_progress" || rc=1

  after_sha="$(file_sha256 "$draft")"
  assert_equal "$after_sha" "$before_sha" || rc=1
  return $rc
}

# 2. Existing-real-target protection: a real plan file at the target is
#    refused (non-zero), stays byte-identical, no symlink, no ledger row.
scn2_existing_real_target() {
  local rc=0
  local root draft target index before_sha after_sha

  root="$(new_fixture "02-existing-real-target")" || return 1
  assert_fixture_isolated "$root" || return 1
  draft="$(make_draft "$root" "PLAN-bridge-dup-01")" || return 1
  mkdir -p "$root/docs/plan"
  target="$root/docs/plan/PLAN-bridge-dup-01-v1.0.md"
  printf 'REAL PLAN FILE - must survive promotion attempts\n' > "$target"
  before_sha="$(file_sha256 "$target")"

  run_promote "$BRIDGE_SCRIPT" "$root" "bridge-dup-01" "$draft" "run1"
  if [[ "$RC_LAST" -eq 0 ]]; then echo "  expected non-zero exit, got 0" >&2; rc=1; fi

  after_sha="$(file_sha256 "$target")"
  assert_equal "$after_sha" "$before_sha" || rc=1
  if [[ -L "$target" ]]; then echo "  target must not have become a symlink" >&2; rc=1; fi
  assert_no_ledger_row "$root" "bridge-dup-01" || rc=1
  return $rc
}

# 3. doc_garden absent: promotion from a bridge copy with no doc_garden.sh
#    beside it exits non-zero, stderr names doc_garden, no symlink, no ledger
#    row, no success claim on stdout.
scn3_doc_garden_absent() {
  local rc=0
  local root draft target

  root="$(new_fixture "03-doc-garden-absent")" || return 1
  assert_fixture_isolated "$root" || return 1
  mkdir -p "$root/bin"
  cp "$BRIDGE_SCRIPT" "$root/bin/bridge_superpowers.sh"
  chmod +x "$root/bin/bridge_superpowers.sh"
  draft="$(make_draft "$root" "PLAN-bridge-nogarden-01")" || return 1

  run_promote "$root/bin/bridge_superpowers.sh" "$root" "bridge-nogarden-01" "$draft" "run1"
  if [[ "$RC_LAST" -eq 0 ]]; then echo "  expected non-zero exit, got 0" >&2; rc=1; fi

  assert_contains "$(cat "$root/run1.stderr")" "doc_garden" || rc=1

  target="$root/docs/plan/PLAN-bridge-nogarden-01-v1.0.md"
  if [[ -L "$target" || -e "$target" ]]; then echo "  no target symlink expected at '$target'" >&2; rc=1; fi
  assert_no_ledger_row "$root" "bridge-nogarden-01" || rc=1
  refute_contains "$(cat "$root/run1.stdout")" "Successfully promoted" || rc=1
  return $rc
}

# 4. doc_garden present but failing after symlink creation: exit non-zero,
#    the created symlink is rolled back (target absent), no ledger row.
scn4_doc_garden_fails() {
  local rc=0
  local root draft target

  root="$(new_fixture "04-doc-garden-fails")" || return 1
  assert_fixture_isolated "$root" || return 1
  mkdir -p "$root/bin"
  cp "$BRIDGE_SCRIPT" "$root/bin/bridge_superpowers.sh"
  chmod +x "$root/bin/bridge_superpowers.sh"
  cat > "$root/bin/doc_garden.sh" <<'MOCKEOF'
#!/usr/bin/env bash
echo "mock doc_garden.sh failing as configured"
exit 1
MOCKEOF
  chmod +x "$root/bin/doc_garden.sh"
  draft="$(make_draft "$root" "PLAN-bridge-gardenfail-01")" || return 1

  run_promote "$root/bin/bridge_superpowers.sh" "$root" "bridge-gardenfail-01" "$draft" "run1"
  if [[ "$RC_LAST" -eq 0 ]]; then echo "  expected non-zero exit, got 0" >&2; rc=1; fi

  target="$root/docs/plan/PLAN-bridge-gardenfail-01-v1.0.md"
  if [[ -L "$target" || -e "$target" ]]; then echo "  expected symlink rollback (target absent): '$target'" >&2; rc=1; fi
  assert_no_ledger_row "$root" "bridge-gardenfail-01" || rc=1
  refute_contains "$(cat "$root/run1.stdout")" "Successfully promoted" || rc=1
  return $rc
}

# 5. Idempotent re-promotion: a second promote with the same task-id exits 0,
#    the symlink still resolves, and the ledger holds exactly one row.
scn5_idempotent() {
  local rc=0
  local root draft target index count

  root="$(new_fixture "05-idempotent")" || return 1
  assert_fixture_isolated "$root" || return 1
  draft="$(make_draft "$root" "PLAN-bridge-idem-01")" || return 1

  run_promote "$BRIDGE_SCRIPT" "$root" "bridge-idem-01" "$draft" "run1"
  assert_equal "$RC_LAST" 0 || rc=1

  run_promote "$BRIDGE_SCRIPT" "$root" "bridge-idem-01" "$draft" "run2"
  assert_equal "$RC_LAST" 0 || rc=1

  target="$root/docs/plan/PLAN-bridge-idem-01-v1.0.md"
  if [[ ! -L "$target" ]]; then echo "  expected symlink at '$target'" >&2; rc=1; fi
  if [[ ! -e "$target" ]]; then echo "  expected symlink to resolve: '$target'" >&2; rc=1; fi

  index="$root/docs/task/task-index.md"
  if [[ ! -f "$index" ]]; then echo "  expected task-index at '$index'" >&2; rc=1; fi
  count="$(grep -Fc -- '- TASK-bridge-idem-01 |' "$index")"
  assert_equal "$count" "1" || rc=1
  return $rc
}

# 6. doc_garden exits 0 WITHOUT registering: the F2b post-condition must refuse
#    the success claim — exit non-zero, created symlink rolled back, no ledger
#    row, no "Successfully promoted" on stdout.
scn6_doc_garden_exits0_no_register() {
  local rc=0
  local root draft target

  root="$(new_fixture "06-doc-garden-silent-success")" || return 1
  assert_fixture_isolated "$root" || return 1
  mkdir -p "$root/bin"
  cp "$BRIDGE_SCRIPT" "$root/bin/bridge_superpowers.sh"
  chmod +x "$root/bin/bridge_superpowers.sh"
  # The bridge copy sources the shared fence-aware reader for the F8
  # post-condition; give the fixture the same adapter files so the check runs
  # real reader logic against the (absent) ledger instead of failing to source.
  if [[ ! -f "$BRIDGE_SCRIPT_DIR/codeguide_doc_lines.sh" || ! -f "$BRIDGE_SCRIPT_DIR/shadow_doc_parse.py" ]]; then
    echo "  scenario 06 needs codeguide_doc_lines.sh and shadow_doc_parse.py beside the bridge script" >&2
    return 1
  fi
  cp "$BRIDGE_SCRIPT_DIR/codeguide_doc_lines.sh" "$root/bin/"
  cp "$BRIDGE_SCRIPT_DIR/shadow_doc_parse.py" "$root/bin/"
  cat > "$root/bin/doc_garden.sh" <<'MOCKEOF'
#!/usr/bin/env bash
echo "mock doc_garden.sh exiting 0 without registering anything"
exit 0
MOCKEOF
  chmod +x "$root/bin/doc_garden.sh"
  draft="$(make_draft "$root" "PLAN-bridge-silent-01")" || return 1

  run_promote "$root/bin/bridge_superpowers.sh" "$root" "bridge-silent-01" "$draft" "run1"
  if [[ "$RC_LAST" -eq 0 ]]; then echo "  expected non-zero exit, got 0" >&2; rc=1; fi

  target="$root/docs/plan/PLAN-bridge-silent-01-v1.0.md"
  if [[ -L "$target" || -e "$target" ]]; then echo "  expected symlink rollback (target absent): '$target'" >&2; rc=1; fi
  refute_contains "$(cat "$root/run1.stdout")" "Successfully promoted" || rc=1
  assert_no_ledger_row "$root" "bridge-silent-01" || rc=1
  return $rc
}

# 7. Guard refuses a symlink pointing elsewhere: pre-existing symlink at the
#    target pointing at a DIFFERENT file is refused (exit 1), left byte-identical
#    (readlink unchanged), no ledger row.
scn7_guard_refuses_foreign_symlink() {
  local rc=0
  local root draft target other_file rel_other readlink_before readlink_after

  root="$(new_fixture "07-foreign-symlink-refused")" || return 1
  assert_fixture_isolated "$root" || return 1
  draft="$(make_draft "$root" "PLAN-bridge-foreign-01")" || return 1
  mkdir -p "$root/docs/plan"
  other_file="$root/.superpowers/plans/PLAN-other-target.md"
  printf '# PLAN-other-target\n- objective: not the promoted draft\n' > "$other_file"
  target="$root/docs/plan/PLAN-bridge-foreign-01-v1.0.md"
  rel_other="$(python3 -c "import sys, os; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$other_file" "$root/docs/plan")"
  ln -s "$rel_other" "$target"
  readlink_before="$(readlink "$target")"

  run_promote "$BRIDGE_SCRIPT" "$root" "bridge-foreign-01" "$draft" "run1"
  if [[ "$RC_LAST" -eq 0 ]]; then echo "  expected non-zero exit, got 0" >&2; rc=1; fi

  if [[ ! -L "$target" ]]; then echo "  expected the foreign symlink to remain a symlink" >&2; rc=1; fi
  readlink_after="$(readlink "$target")"
  assert_equal "$readlink_after" "$readlink_before" || rc=1
  assert_no_ledger_row "$root" "bridge-foreign-01" || rc=1
  return $rc
}

# 8. Draft is a symlink to a directory: F7 requires a REGULAR draft file, so
#    the promotion is refused (exit non-zero) before any write — no target
#    symlink, no ledger row, no success claim on stdout.
scn8_draft_symlink_to_directory() {
  local rc=0
  local root draft_link target

  root="$(new_fixture "08-draft-symlink-to-dir")" || return 1
  assert_fixture_isolated "$root" || return 1
  mkdir -p "$root/.superpowers/plans"
  draft_link="$root/.superpowers/draft-link"
  ln -s "$root/.superpowers/plans" "$draft_link"

  run_promote "$BRIDGE_SCRIPT" "$root" "bridge-dirdraft-01" "$draft_link" "run1"
  if [[ "$RC_LAST" -eq 0 ]]; then echo "  expected non-zero exit, got 0" >&2; rc=1; fi

  target="$root/docs/plan/PLAN-bridge-dirdraft-01-v1.0.md"
  if [[ -L "$target" || -e "$target" ]]; then echo "  no target symlink expected at '$target'" >&2; rc=1; fi
  assert_no_ledger_row "$root" "bridge-dirdraft-01" || rc=1
  refute_contains "$(cat "$root/run1.stdout")" "Successfully promoted" || rc=1
  return $rc
}

# 9. Live row with a malformed status: mock doc_garden exits 0 but writes a
#    LIVE UNFENCED row `- TASK-<id> | in_progress_stale | ...` plus valid task
#    capsule and ORCH scaffold — only the status field is wrong. F10 requires
#    the exact row prefix `- TASK-<id> | in_progress |`, so the post-condition
#    must refuse: exit non-zero, created symlink rolled back, no success claim.
scn9_malformed_status_live_row() {
  local rc=0
  local root draft target

  root="$(new_fixture "09-stale-status-live-row")" || return 1
  assert_fixture_isolated "$root" || return 1
  mkdir -p "$root/bin"
  cp "$BRIDGE_SCRIPT" "$root/bin/bridge_superpowers.sh"
  chmod +x "$root/bin/bridge_superpowers.sh"
  # Same shared fence-aware reader adapter copies as scenario 06.
  if [[ ! -f "$BRIDGE_SCRIPT_DIR/codeguide_doc_lines.sh" || ! -f "$BRIDGE_SCRIPT_DIR/shadow_doc_parse.py" ]]; then
    echo "  scenario 09 needs codeguide_doc_lines.sh and shadow_doc_parse.py beside the bridge script" >&2
    return 1
  fi
  cp "$BRIDGE_SCRIPT_DIR/codeguide_doc_lines.sh" "$root/bin/"
  cp "$BRIDGE_SCRIPT_DIR/shadow_doc_parse.py" "$root/bin/"
  cat > "$root/bin/doc_garden.sh" <<'MOCKEOF'
#!/usr/bin/env bash
# Mock: exits 0 and writes a LIVE (unfenced) ledger row whose status field is
# only PREFIXED with in_progress, plus the task capsule and ORCH scaffold, so
# the F10 post-condition is the only thing that can catch the bad status.
echo "mock doc_garden.sh writing an in_progress_stale row"
printf '# Task Index\n\n## In Progress\n\n- TASK-bridge-stale-01 | in_progress_stale | bad status\n' > "docs/task/task-index.md"
printf '# TASK-bridge-stale-01\n\n- status: in_progress_stale\n' > "docs/task/TASK-bridge-stale-01.md"
printf '# ORCH-bridge-stale-01\n\n- task_id: bridge-stale-01\n' > "docs/orchestration/bridge-stale-01/ORCH.md"
exit 0
MOCKEOF
  chmod +x "$root/bin/doc_garden.sh"
  draft="$(make_draft "$root" "PLAN-bridge-stale-01")" || return 1

  run_promote "$root/bin/bridge_superpowers.sh" "$root" "bridge-stale-01" "$draft" "run1"
  if [[ "$RC_LAST" -eq 0 ]]; then echo "  expected non-zero exit, got 0" >&2; rc=1; fi

  target="$root/docs/plan/PLAN-bridge-stale-01-v1.0.md"
  if [[ -L "$target" || -e "$target" ]]; then echo "  expected symlink rollback (target absent): '$target'" >&2; rc=1; fi
  refute_contains "$(cat "$root/run1.stdout")" "Successfully promoted" || rc=1
  return $rc
}

# ------------------------------------------------------------------ main ---

run_scenario "01 happy-path promote" scn1_happy_path
run_scenario "02 existing-real-target protection" scn2_existing_real_target
run_scenario "03 doc_garden absent" scn3_doc_garden_absent
run_scenario "04 doc_garden failing after symlink" scn4_doc_garden_fails
run_scenario "05 idempotent re-promotion" scn5_idempotent
run_scenario "06 doc_garden exits 0 without registering" scn6_doc_garden_exits0_no_register
run_scenario "07 guard refuses symlink pointing elsewhere" scn7_guard_refuses_foreign_symlink
run_scenario "08 draft symlink to a directory refused" scn8_draft_symlink_to_directory
run_scenario "09 malformed-status live row refused" scn9_malformed_status_live_row

echo
echo "summary: $PASS_COUNT passed, $FAIL_COUNT failed"
if [[ $FAIL_COUNT -eq 0 ]]; then
  rm -rf "$FIXTURES_ROOT"
  echo "fixtures cleaned up: $FIXTURES_ROOT"
  exit 0
else
  echo "fixtures kept for inspection: $FIXTURES_ROOT"
  exit 1
fi
