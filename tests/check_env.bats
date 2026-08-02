#!/usr/bin/env bats

load codeguide_helper

CHECK_ENV="$SCRIPTS_DIR/check_env.sh"
CHECK_ALL="$SCRIPTS_DIR/check_all.sh"

# Build a stub toolchain dir so the checks are deterministic regardless of
# what the caller's machine has installed. Core utilities (grep, cut, head,
# dirname) still come from /usr/bin:/bin appended after the stubs.
write_stub_toolchain() {
  local stub_dir="$1"
  local pytest_importable="$2"

  mkdir -p "$stub_dir"

  cat > "$stub_dir/python3" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-c" ]]; then
  case "\${2:-}" in
    *"import pytest"*"print"*) echo "8.0.0"; exit $([[ "$pytest_importable" == "true" ]] && echo 0 || echo 1) ;;
    *"import pytest"*) exit $([[ "$pytest_importable" == "true" ]] && echo 0 || echo 1) ;;
    *"version_info"*) exit 0 ;;
    *"sys.version_info[:3]"*) echo "3.12.0"; exit 0 ;;
  esac
fi
exit 0
EOF
  chmod +x "$stub_dir/python3"

  cat > "$stub_dir/bats" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "--version" ]] && { echo "Bats 1.11.0"; exit 0; }
exit 0
EOF
  chmod +x "$stub_dir/bats"

  cat > "$stub_dir/git" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "--version" ]] && { echo "git version 2.44.0"; exit 0; }
exit 0
EOF
  chmod +x "$stub_dir/git"
}

@test "check_env --help prints usage and exits 0" {
  run bash "$CHECK_ENV" --help
  [ "$status" -eq 0 ]
  assert_contains "$output" "Usage:"
  assert_contains "$output" "--skip-pytest"
}

@test "check_env passes with a complete stub toolchain" {
  local stub_dir="$TEST_WORKSPACE/stub-full"
  write_stub_toolchain "$stub_dir" "true"

  run env PATH="$stub_dir:/usr/bin:/bin" bash "$CHECK_ENV"
  [ "$status" -eq 0 ]
  assert_contains "$output" "[RESULT] Environment check passed."
}

@test "check_env fails with remediation when bats is missing" {
  local stub_dir="$TEST_WORKSPACE/stub-nobats"
  write_stub_toolchain "$stub_dir" "true"
  rm "$stub_dir/bats"

  run env PATH="$stub_dir:/usr/bin:/bin" bash "$CHECK_ENV"
  [ "$status" -eq 1 ]
  assert_contains "$output" "bats not found on PATH"
  assert_contains "$output" "remediation:"
}

@test "check_env fails when pytest is not importable and passes with --skip-pytest" {
  local stub_dir="$TEST_WORKSPACE/stub-nopytest"
  write_stub_toolchain "$stub_dir" "false"

  run env PATH="$stub_dir:/usr/bin:/bin" bash "$CHECK_ENV"
  [ "$status" -eq 1 ]
  assert_contains "$output" "pytest is not importable"

  run env PATH="$stub_dir:/usr/bin:/bin" bash "$CHECK_ENV" --skip-pytest
  [ "$status" -eq 0 ]
  assert_contains "$output" "pytest check skipped"
}

@test "check_env rejects unknown options" {
  run bash "$CHECK_ENV" --frobnicate
  [ "$status" -eq 2 ]
  assert_contains "$output" "Unknown option"
}

@test "check_all --help prints the gate description and exits 0" {
  run bash "$CHECK_ALL" --help
  [ "$status" -eq 0 ]
  assert_contains "$output" "Single quality gate"
}

@test "check_all rejects unknown options" {
  run bash "$CHECK_ALL" --frobnicate
  [ "$status" -eq 2 ]
  assert_contains "$output" "Unknown option"
}
