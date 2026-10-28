#!/usr/bin/env bats

load codeguide_helper

PACKAGING_SMOKE() {
  python3 "$SCRIPTS_DIR/packaging_smoke.py" "$@"
}

# Seeds a full scratch skill-root fixture under $1, independent of the real
# skill repo, hitting all three classification outcomes plus the specific
# traps the tool's classify() docstring calls out:
#   - .DS_Store and __pycache__/*.pyc NESTED inside scripts/ and tests/
#     (SHIP-allowlisted directories) -- must classify DEV-ARTIFACT, not
#     SHIP, proving the DEV-ARTIFACT-before-SHIP precedence.
#   - an empty allowlisted directory (scripts/empty-ship-subdir) -- must
#     still classify SHIP via its own path.
#   - an empty stray directory (test/) mirroring the real tree's known
#     stray, plus a non-empty stray directory and a hostile
#     prefix-collision sibling (scripts2/, tests-legacy/) -- must all land
#     UNKNOWN, never swept into scripts/**/tests/** by substring matching.
#   - a filename containing a space, both under an allowlisted dir (SHIP)
#     and under a stray dir (UNKNOWN).
_seed_packaging_fixture() {
  local root="$1"
  mkdir -p "$root"

  # SHIP: exact top-level files.
  printf '# skill\n' > "$root/SKILL.md"
  printf '# readme\n' > "$root/README.md"
  printf '# English readme\n' > "$root/README.en.md"
  printf 'pytest\n' > "$root/requirements-dev.txt"

  # SHIP: allowlisted directories, including a name-with-spaces file and an
  # empty allowlisted subdirectory (must still classify SHIP).
  mkdir -p "$root/agents" "$root/case-studies" "$root/config" "$root/references" "$root/scripts" \
    "$root/tests" "$root/scripts/empty-ship-subdir"
  printf '<html></html>\n' > "$root/case-studies/report.html"
  printf 'agent\n' > "$root/agents/default-prompt.yaml"
  printf '{}\n' > "$root/config/ai_model_registry.json"
  printf 'ref\n' > "$root/references/notes.md"
  printf 'print(1)\n' > "$root/scripts/my script.py"
  printf 'def test(): pass\n' > "$root/tests/test_x.py"

  # DEV-ARTIFACT: root-rooted directories.
  mkdir -p "$root/.git/objects" "$root/.serena/cache" "$root/.pytest_cache" "$root/.gemini" "$root/tmp"
  printf 'ref: refs/heads/main\n' > "$root/.git/HEAD"
  printf 'cache\n' > "$root/.serena/cache/x.bin"
  printf 'v\n' > "$root/.pytest_cache/CACHEDIR.TAG"
  printf '{}\n' > "$root/.gemini/settings.json"
  printf 'scratch\n' > "$root/tmp/scratch.md"

  # DEV-ARTIFACT: top-level exact files.
  printf '*.pyc\n' > "$root/.gitignore"
  printf 'ds\n' > "$root/.DS_Store"

  # DEV-ARTIFACT: anywhere-basename rules NESTED inside SHIP-allowlisted
  # directories -- must win over the scripts/**/tests/** SHIP globs, the
  # same shape the real skill tree has today.
  mkdir -p "$root/scripts/__pycache__" "$root/tests/__pycache__"
  printf 'ds\n' > "$root/scripts/.DS_Store"
  printf 'bytecode\n' > "$root/scripts/__pycache__/mod.cpython-311.pyc"
  printf 'bytecode\n' > "$root/tests/__pycache__/mod.cpython-311.pyc"
  # a stray .pyc NOT inside any __pycache__ dir
  printf 'bytecode\n' > "$root/scripts/stray.pyc"

  # UNKNOWN: an empty stray directory (mirrors the real tree's empty test/
  # dir), a non-empty stray directory, and a hostile prefix-collision
  # sibling of an allowlisted root.
  mkdir -p "$root/test" "$root/weird folder" "$root/scripts2" "$root/tests-legacy"
  printf 'mystery\n' > "$root/weird folder/file.txt"
  printf 'evil\n' > "$root/scripts2/evil.py"
  printf 'old\n' > "$root/tests-legacy/old.py"
}

@test "packaging smoke classifies SHIP, DEV-ARTIFACT, and UNKNOWN on a scratch fixture" {
  local root="$TEST_WORKSPACE/skill-fixture"
  _seed_packaging_fixture "$root"

  run PACKAGING_SMOKE --skill-root "$root" --format json --manifest
  [ "$status" -eq 1 ]
  python3 - "$output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["schema"] == "codeguide-packaging-smoke/1", payload
ship = set(payload["ship_manifest"])
unknown = set(payload["unknown"])

for expected in (
    "SKILL.md", "README.md", "README.en.md", "requirements-dev.txt",
    "agents/default-prompt.yaml", "case-studies/report.html", "config/ai_model_registry.json",
    "references/notes.md", "scripts/my script.py", "tests/test_x.py",
    "scripts/empty-ship-subdir",
):
    assert expected in ship, (expected, ship)

for not_ship in (
    "scripts/.DS_Store", "scripts/__pycache__/mod.cpython-311.pyc",
    "tests/__pycache__/mod.cpython-311.pyc", "scripts/stray.pyc",
    ".gitignore", ".DS_Store",
):
    assert not_ship not in ship, (not_ship, ship)

for expected in ("test", "weird folder/file.txt", "scripts2/evil.py", "tests-legacy/old.py"):
    assert expected in unknown, (expected, unknown)
assert "scripts/my script.py" not in unknown

assert payload["ship_count"] == len(ship)
assert payload["dev_artifact_count"] > 0
PY
}

@test "packaging smoke text format reports DEV-ARTIFACT summary buckets and the full UNKNOWN list" {
  local root="$TEST_WORKSPACE/skill-fixture-text"
  _seed_packaging_fixture "$root"

  run PACKAGING_SMOKE --skill-root "$root" --no-exit-code
  [ "$status" -eq 0 ]
  assert_contains "$output" "# Packaging Smoke Report ($(cd "$root" && pwd -P))"
  assert_contains "$output" "## DEV-ARTIFACT summary"
  assert_contains "$output" ".git/**: "
  assert_contains "$output" "__pycache__/**: 2"
  assert_contains "$output" "*.pyc: 1"
  assert_contains "$output" ".DS_Store: 2"
  assert_contains "$output" "UNKNOWN (4)"
  assert_contains "$output" "  test"
  assert_contains "$output" "  weird folder/file.txt"
  assert_contains "$output" "  scripts2/evil.py"
  assert_contains "$output" "  tests-legacy/old.py"
}

@test "packaging smoke exits 0 by default when nothing is UNKNOWN" {
  local root="$TEST_WORKSPACE/skill-fixture-clean"
  mkdir -p "$root/agents" "$root/config" "$root/references" "$root/scripts" "$root/tests"
  printf 's\n' > "$root/SKILL.md"
  printf 'r\n' > "$root/README.md"
  printf 'd\n' > "$root/requirements-dev.txt"
  printf 'a\n' > "$root/agents/a.yaml"

  run PACKAGING_SMOKE --skill-root "$root"
  [ "$status" -eq 0 ]
  assert_contains "$output" "unknown_count: 0"
}

@test "packaging smoke --no-exit-code stays 0 even though UNKNOWN paths are reported" {
  local root="$TEST_WORKSPACE/skill-fixture-no-exit-code"
  _seed_packaging_fixture "$root"

  run PACKAGING_SMOKE --skill-root "$root" --no-exit-code
  [ "$status" -eq 0 ]
  assert_contains "$output" "unknown_count: 4"
}

@test "packaging smoke classifies a symlink by its own path and never follows it into another tree" {
  local root="$TEST_WORKSPACE/skill-fixture-symlink"
  mkdir -p "$root/scripts"
  printf 's\n' > "$root/SKILL.md"

  local outside="$TEST_WORKSPACE/outside-target"
  mkdir -p "$outside"
  printf 'external\n' > "$outside/leaked.txt"
  printf 'external\n' > "$outside/leaked2.txt"

  ln -s "$outside" "$root/scripts/dir_link"
  ln -s "$outside/leaked.txt" "$root/scripts/file_link"
  ln -s "/nonexistent/target-does-not-exist" "$root/scripts/dangling_link"

  run PACKAGING_SMOKE --skill-root "$root" --format json --manifest --no-exit-code
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
ship = payload["ship_manifest"]

# The symlinks themselves are classified (all live under scripts/ -> SHIP).
assert "scripts/dir_link" in ship, ship
assert "scripts/file_link" in ship, ship
assert "scripts/dangling_link" in ship, ship

# The symlinked directory's contents must NOT have been traversed: nothing
# from outside-target leaked into the manifest under dir_link/.
assert not any(p.startswith("scripts/dir_link/") for p in ship), ship
assert not any("leaked" in p for p in payload["unknown"] + ship), payload
PY
}

@test "packaging smoke never lets a sibling directory name substring-match an allowlisted root" {
  local root="$TEST_WORKSPACE/skill-fixture-prefix"
  mkdir -p "$root/scripts2" "$root/tests-legacy"
  printf 's\n' > "$root/SKILL.md"
  printf 'x\n' > "$root/scripts2/evil.py"
  printf 'y\n' > "$root/tests-legacy/old.py"

  run PACKAGING_SMOKE --skill-root "$root" --format json --no-exit-code
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
unknown = set(payload["unknown"])
assert "scripts2/evil.py" in unknown, unknown
assert "tests-legacy/old.py" in unknown, unknown
PY
}

@test "packaging smoke handles paths containing spaces without shell-splitting them" {
  local root="$TEST_WORKSPACE/skill-fixture-spaces"
  mkdir -p "$root/scripts" "$root/odd name here"
  printf 's\n' > "$root/SKILL.md"
  printf 'p\n' > "$root/scripts/has space.py"
  printf 'p\n' > "$root/odd name here/file.txt"

  run PACKAGING_SMOKE --skill-root "$root" --format json --manifest --no-exit-code
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert "scripts/has space.py" in payload["ship_manifest"], payload["ship_manifest"]
assert "odd name here/file.txt" in payload["unknown"], payload["unknown"]
PY
}

@test "packaging smoke exits 2 with an error when --skill-root is not a directory" {
  run PACKAGING_SMOKE --skill-root "$TEST_WORKSPACE/does-not-exist"
  [ "$status" -eq 2 ]
  assert_contains "$output" "error:"
}

@test "packaging smoke rejects an unknown --format value with exit 2 (argparse contract)" {
  run PACKAGING_SMOKE --format bogus
  [ "$status" -eq 2 ]
}

@test "packaging smoke runs against the real skill root without crashing and reports well-formed sections" {
  run PACKAGING_SMOKE --no-exit-code
  [ "$status" -eq 0 ]
  assert_contains "$output" "# Packaging Smoke Report"
  assert_contains "$output" "- ship_count:"
  assert_contains "$output" "- dev_artifact_count:"
  assert_contains "$output" "- unknown_count:"
  assert_contains "$output" "## DEV-ARTIFACT summary"
  assert_contains "$output" "## UNKNOWN"

  local ship_line ship_count
  ship_line="$(printf '%s\n' "$output" | grep '^- ship_count:')"
  ship_count="$(printf '%s' "$ship_line" | grep -oE '[0-9]+')"
  [ -n "$ship_count" ]
  [ "$ship_count" -gt 50 ]
}

@test "packaging smoke --format json on the real skill root parses and matches the text-mode counts" {
  run PACKAGING_SMOKE --no-exit-code --format json
  [ "$status" -eq 0 ]
  local json_output="$output"

  run PACKAGING_SMOKE --no-exit-code
  [ "$status" -eq 0 ]
  local text_output="$output"

  python3 - "$json_output" "$text_output" <<'PY'
import json
import re
import sys

payload = json.loads(sys.argv[1])
text = sys.argv[2]

assert payload["schema"] == "codeguide-packaging-smoke/1"
assert isinstance(payload["unknown"], list)
assert "ship_manifest" not in payload  # --manifest not passed

text_ship = int(re.search(r"^- ship_count: (\d+)$", text, re.MULTILINE).group(1))
text_dev = int(re.search(r"^- dev_artifact_count: (\d+)$", text, re.MULTILINE).group(1))
text_unknown = int(re.search(r"^- unknown_count: (\d+)$", text, re.MULTILINE).group(1))
assert text_ship == payload["ship_count"], (text_ship, payload["ship_count"])
assert text_dev == payload["dev_artifact_count"], (text_dev, payload["dev_artifact_count"])
assert text_unknown == len(payload["unknown"]), (text_unknown, payload["unknown"])
PY
}

@test "packaging smoke --manifest adds the full SHIP path list on the real skill root" {
  run PACKAGING_SMOKE --no-exit-code --format json --manifest
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert "ship_manifest" in payload
assert len(payload["ship_manifest"]) == payload["ship_count"]
assert "SKILL.md" in payload["ship_manifest"]
assert "README.md" in payload["ship_manifest"]
assert "README.en.md" in payload["ship_manifest"]
PY
}
