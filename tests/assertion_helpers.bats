#!/usr/bin/env bats

load codeguide_helper

# Guard for the tracked issue. The whole suite depends on
# these helpers failing their test from ANY position in the body, and that rests on
# one property: under `set -e` a failing helper CALL aborts, while a failing bare
# `[[ ]]` does not on stock macOS bash 3.2.57. These tests exercise that property in
# a plain errexit shell rather than nesting bats inside bats (which the suite avoids
# for the same reason front_cli.bats documents).

_run_under_errexit() {
  # $1 = script body executed with errexit on and the helpers sourced.
  local helper
  helper="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/codeguide_helper.bash"
  run env BATS_TEST_FILENAME="$BATS_TEST_FILENAME" bash -c "set -e; source '$helper'; $1"
}

@test "a failing assert_contains aborts an errexit shell (the property the suite relies on)" {
  _run_under_errexit 'assert_contains "hello" "THIS-DOES-NOT-EXIST"; echo REACHED'
  [ "$status" -ne 0 ]
  refute_contains "$output" "REACHED"
}

@test "a failing bare [[ ]] does NOT abort — the reason the helpers exist" {
  _run_under_errexit '[[ "hello" == *"THIS-DOES-NOT-EXIST"* ]]; echo REACHED'
  # Documents the platform behavior this conversion works around. If a future bash
  # starts aborting here, this test is the canary that the workaround can be revisited.
  [ "$status" -eq 0 ]
  assert_contains "$output" "REACHED"
}

@test "a passing assert_contains does not abort" {
  _run_under_errexit 'assert_contains "hello world" "lo wo"; echo REACHED'
  [ "$status" -eq 0 ]
  assert_contains "$output" "REACHED"
}

@test "refute_contains aborts when the needle IS present and passes when it is absent" {
  _run_under_errexit 'refute_contains "hello" "hell"; echo REACHED'
  [ "$status" -ne 0 ]
  refute_contains "$output" "REACHED"

  _run_under_errexit 'refute_contains "hello" "goodbye"; echo REACHED'
  [ "$status" -eq 0 ]
  assert_contains "$output" "REACHED"
}

@test "assert_equal aborts on a difference and passes on an exact match" {
  _run_under_errexit 'assert_equal "abc" "abd"; echo REACHED'
  [ "$status" -ne 0 ]
  refute_contains "$output" "REACHED"

  _run_under_errexit 'assert_equal "abc" "abc"; assert_equal "" ""; echo REACHED'
  [ "$status" -eq 0 ]
  assert_contains "$output" "REACHED"
}

@test "helpers print both the expected needle and the actual haystack on failure" {
  _run_under_errexit 'assert_contains "haystack-value" "needle-value"'
  [ "$status" -ne 0 ]
  assert_contains "$output" "expected to find: needle-value"
  assert_contains "$output" "haystack-value"

  _run_under_errexit 'refute_contains "haystack-value" "stack"'
  [ "$status" -ne 0 ]
  assert_contains "$output" "expected NOT to find: stack"
}

@test "assert_contains rejects an empty needle instead of passing vacuously" {
  _run_under_errexit 'assert_contains "anything" ""; echo REACHED'
  [ "$status" -ne 0 ]
  refute_contains "$output" "REACHED"
  assert_contains "$output" "empty needle"
}

@test "assert_contains treats glob-special and multiline needles literally" {
  local haystack
  haystack="$(printf 'a[b]c*d\nsecond line')"
  assert_contains "$haystack" "a[b]c*d"
  assert_contains "$haystack" "$haystack"
  # A glob that WOULD match if the needle were treated as a pattern must not match.
  refute_contains "$haystack" "a[b]c?d"
}
