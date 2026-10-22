#!/usr/bin/env bats

load codeguide_helper

# A pipeline whose consumer exits early (`grep -q`, `grep -m1`, `head -n N`) while the producer is
# still writing kills the producer with SIGPIPE; under `set -o pipefail` that failure becomes the
# pipeline's status even though the consumer found what it wanted. It surfaced here as registry ids
# reported missing at random, as a doc_garden abort on long change lists, and as validate_docs
# skipping its empty-shadow-graph gate on large repositories. These tests pin that class of defect:
# the hazard itself (control), the replacement helpers, the sites with a deterministic symptom, and
# a static scan that keeps the pattern out of scripts/.

# list_has_line must answer exactly like `grep -Fx` (whole line, fixed string, case-sensitive).
agrees_with_grep() {
  local list="$1" needle="$2" want got

  if grep -Fxq -- "$needle" <<<"$list"; then want=yes; else want=no; fi
  if list_has_line "$list" "$needle"; then got=yes; else got=no; fi
  if [[ "$want" != "$got" ]]; then
    printf 'list_has_line disagrees with grep -Fx: list=[%s] needle=[%s] grep=%s helper=%s\n' \
      "$list" "$needle" "$want" "$got" >&2
    return 1
  fi
}

@test "control: printf into grep -q fails under pipefail on a list larger than the pipe buffer although the line is present" {
  run bash -c 'set -o pipefail
    list="$(seq -f "validator.id.%g@v1" 1 8000)"
    printf "%s\n" "$list" | grep -Fxq -- "validator.id.1@v1"'
  [ "$status" -ne 0 ]
}

@test "list_has_line finds present lines and rejects absent ones in a list far larger than the pipe buffer" {
  run bash -c 'set -euo pipefail
    source "$1/validate_docs.d/20-rules-shadow.sh"
    list="$(seq -f "validator.id.%g@v1" 1 8000)"
    list_has_line "$list" "validator.id.1@v1"
    list_has_line "$list" "validator.id.4000@v1"
    list_has_line "$list" "validator.id.8000@v1"
    if list_has_line "$list" "validator.id.9999@v1"; then exit 3; fi
    if list_has_line "$list" "validator.id.1"; then exit 4; fi' _ "$SCRIPTS_DIR"
  [ "$status" -eq 0 ]
}

@test "list_has_line answers exactly like grep -Fx" {
  source "$SCRIPTS_DIR/validate_docs.d/20-rules-shadow.sh"

  agrees_with_grep $'a\nb\nc' "a"
  agrees_with_grep $'a\nb\nc' "b"
  agrees_with_grep $'a\nb\nc' "c"
  agrees_with_grep $'ab\nb' "a"
  agrees_with_grep $'a\nb' "ab"
  agrees_with_grep "abc" "*"
  agrees_with_grep "*" "*"
  agrees_with_grep "abc" "a?c"
  agrees_with_grep "a?c" "a?c"
  agrees_with_grep "a" "[a]"
  agrees_with_grep "[a]" "[a]"
  agrees_with_grep "abc" "a.c"
  agrees_with_grep "a.c" "a.c"
  agrees_with_grep $'a b\nc' "a b"
  agrees_with_grep $'a b\nc' "a"
  agrees_with_grep "" "x"
  agrees_with_grep "A" "a"
  agrees_with_grep "-n" "-n"
  agrees_with_grep 'a\b' 'a\b'
  agrees_with_grep "ab" 'a\b'
  agrees_with_grep "a " "a"
  agrees_with_grep $'x\nx' "x"
  agrees_with_grep "x" "x"
}

@test "is_shadow_bucket matches whole bucket names only" {
  source "$SCRIPTS_DIR/validate_docs.d/20-rules-shadow.sh"
  SHADOW_BUCKETS=(alpha beta)

  is_shadow_bucket "alpha"
  is_shadow_bucket "beta"
  run is_shadow_bucket "alph"
  [ "$status" -ne 0 ]
  run is_shadow_bucket "alpha beta"
  [ "$status" -ne 0 ]
  run is_shadow_bucket ""
  [ "$status" -ne 0 ]
}

@test "check_catalog_probe_coverage reports no mismatch when its id lists are far larger than the pipe buffer" {
  run bash -c 'set -euo pipefail
    SCRIPT_DIR="$1"
    source "$SCRIPT_DIR/validate_docs.d/20-rules-shadow.sh"
    failures=0
    fail() { printf "FAIL %s\n" "$*"; failures=$((failures + 1)); }
    pass() { :; }
    big="$(seq -f "validator.id.%g@v1" 1 8000)"
    collect_policy_loader_ids() {
      case "$1" in
        validators) printf "%s\n" "$big" ;;
        implemented_primary) printf "%s\n" "validator.id.1@v1" "validator.id.4000@v1" "validator.id.8000@v1" ;;
        parser_backed_now) printf "%s\n" "validator.id.1@v1" ;;
        source_probe_only) printf "%s\n" "validator.id.4000@v1" "validator.id.8000@v1" ;;
      esac
    }
    collect_probe_primary_validator_ids() {
      printf "%s\n" "validator.id.1@v1" "validator.id.4000@v1" "validator.id.8000@v1"
    }
    check_catalog_probe_coverage "catalog.md"
    echo "mismatches=$failures"' _ "$SCRIPTS_DIR"
  [ "$status" -eq 0 ]
  assert_contains "$output" "mismatches=0"
  refute_contains "$output" "FAIL"
}

@test "strict validation reports an empty shadow graph however long the tracked-file listing is" {
  # `git ls-files | grep -qv` made the gate read "source exists" as "no source" whenever the listing
  # outgrew the pipe buffer, so a repository with real source and no shadow unit passed strict
  # validation purely because it was big. a.py sorts before docs/ so grep exits long before git does.
  local project="$TEST_WORKSPACE/big-listing"
  mkdir -p "$project"
  "$INIT_SCAFFOLD" "$project" > /dev/null
  git -C "$project" init -q
  printf 'print(1)\n' > "$project/a.py"
  mkdir -p "$project/docs/archive"

  local pad i
  pad="$(printf 'x%.0s' $(seq 1 140))"
  for i in $(seq 1 1500); do
    : > "$project/docs/archive/${pad}-${i}.md"
  done
  git -C "$project" add -A
  [ "$(git -C "$project" ls-files | wc -c | tr -d ' ')" -gt 65536 ]

  run "$VALIDATE" "$project" --mode strict
  assert_contains "$output" "shadow graph is empty"
}

@test "scripts contain no early-exit pipe consumer fed by printf or echo, and no grep -q or grep -m consumer at all" {
  local hits
  hits="$(grep -rnE '\|[[:space:]]*grep[^|]*[[:space:]]-[A-Za-z]*q|\|[[:space:]]*grep[[:space:]]+-m|(printf|echo)[^|]*\|[[:space:]]*head' \
    "$SCRIPTS_DIR" --include='*.sh' --include='codeguide' \
    | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' || true)"

  if [[ -n "$hits" ]]; then
    printf 'early-exit pipe consumers (SIGPIPE under pipefail); use list_has_line, a draining sed -n, or read the whole producer first:\n%s\n' "$hits" >&2
    return 1
  fi
}
