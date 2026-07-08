#!/usr/bin/env bats

load codeguide_helper

METRICS() {
  python3 "$SCRIPTS_DIR/shadow_metrics_report.py" "$@"
}

_write_lines() {
  # $1 = target file, $2 = number of prose lines
  local file="$1" n="$2" i
  {
    printf '# Shadow Unit Overview\n- doc_role: unit_overview\n'
    for ((i = 1; i <= n; i++)); do
      printf 'Prose sentence number %s describing the unit at some length.\n' "$i"
    done
  } > "$file"
}

@test "metrics report summarizes the always-read layer of a fresh scaffold" {
  run METRICS --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"shadow_docs: 7"* ]]
  [[ "$output" == *"always_read_layer: 7 docs"* ]]
  [[ "$output" == *"over_hard_cap(>300): 0"* ]]
}

@test "metrics report flags a doc over the hard cap" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  _write_lines "$DOCS_ROOT/shadow/apps/app-a/overview.md" 320
  run METRICS --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OVER CAP: docs/shadow/apps/app-a/overview.md"* ]]
  [[ "$output" == *"over_hard_cap(>300): 1"* ]]
}

@test "metrics report flags a doc over the soft target but under the cap" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  _write_lines "$DOCS_ROOT/shadow/apps/app-a/overview.md" 240
  run METRICS --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"over target: docs/shadow/apps/app-a/overview.md"* ]]
  [[ "$output" == *"over_hard_cap(>300): 0"* ]]
}

@test "metrics report reports a low routing percentage for a prose-heavy doc" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  _write_lines "$DOCS_ROOT/shadow/apps/app-a/overview.md" 100
  run METRICS --project-root "$TEST_PROJECT" --top 0
  [ "$status" -eq 0 ]
  # 100 prose lines dwarf the 2 structured header lines -> routing near 0%.
  [[ "$output" == *"apps/app-a/overview.md"* ]]
  [[ "$output" == *"routing 2%"* ]] || [[ "$output" == *"routing 1%"* ]] || [[ "$output" == *"routing 0%"* ]]
}

@test "metrics report --exit-code returns 1 when a doc exceeds the soft target" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  _write_lines "$DOCS_ROOT/shadow/apps/app-a/overview.md" 240
  run METRICS --project-root "$TEST_PROJECT" --exit-code
  [ "$status" -eq 1 ]
}

@test "metrics report ignores docs under _deprecated" {
  mkdir -p "$DOCS_ROOT/shadow/_deprecated/apps/app-a"
  _write_lines "$DOCS_ROOT/shadow/_deprecated/apps/app-a/overview.md" 400
  run METRICS --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"over_hard_cap(>300): 0"* ]]
  [[ "$output" != *"OVER CAP"* ]]
}

@test "metrics report counts fenced blocks as code, not routing or prose" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  {
    printf '# Shadow Unit Overview\n- doc_role: unit_overview\n'
    printf '```\n'
    printf 'x = compute(1)\ny = compute(2)\nz = compute(3)\n'
    printf '```\n'
  } > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  run METRICS --project-root "$TEST_PROJECT" --top 0
  [ "$status" -eq 0 ]
  # 3 code lines + 2 fence markers = 5 code; the 2 header lines are routing.
  [[ "$output" == *"apps/app-a/overview.md"* ]]
  [[ "$output" == *"c 5"* ]]
}

@test "metrics report line count matches wc -l (no trailing newline is not over cap)" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  # 301 logical lines joined by \n = exactly 300 newline chars, no trailing newline.
  python3 -c 'import sys; open(sys.argv[1],"w").write(chr(10).join("line %d"%i for i in range(301)))' \
    "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  # Sanity: wc -l sees 300, and the validator's cap is 300, so this must NOT be over cap.
  [ "$(wc -l < "$DOCS_ROOT/shadow/apps/app-a/overview.md" | tr -d ' ')" -eq 300 ]
  run METRICS --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"over_hard_cap(>300): 0"* ]]
  [[ "$output" != *"OVER CAP"* ]]
}

@test "metrics report resolves a skill-package root whose docs live in the parent" {
  local proj="$TEST_WORKSPACE/proj"
  mkdir -p "$proj/pkg/scripts"
  "$INIT_SCAFFOLD" "$proj" >/dev/null 2>&1
  printf 'name: pkg\n' > "$proj/pkg/SKILL.md"
  # pkg has SKILL.md + scripts/ and no docs/ of its own; the parent proj/ has docs/shadow.
  run METRICS --project-root "$proj/pkg"
  [ "$status" -eq 0 ]
  [[ "$output" == *"shadow_docs: 7"* ]]
}

@test "metrics report --exit-code returns 1 for a hard-cap violation too" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  _write_lines "$DOCS_ROOT/shadow/apps/app-a/overview.md" 320
  run METRICS --project-root "$TEST_PROJECT" --exit-code
  [ "$status" -eq 1 ]
}

@test "metrics report keeps a nested 3-backtick line inside a 4-backtick fence as code" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview
- doc_role: unit_overview
````
outer start
```
still inside outer
```
outer end
````
- after: value
EOF
  run METRICS --project-root "$TEST_PROJECT" --top 0
  [ "$status" -eq 0 ]
  # 2 header lines + "- after" = 3 routing; the inner 3-backtick block never closed the outer.
  [[ "$output" == *"r 3"* ]]
}

@test "metrics report rejects an inverted --soft-target/--hard-cap" {
  run METRICS --project-root "$TEST_PROJECT" --soft-target 300 --hard-cap 200
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be <= --hard-cap"* ]]
}

@test "metrics report reports unreadable docs instead of silently dropping them" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  printf '# o\n- doc_role: unit_overview\n' > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  chmod 000 "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  run METRICS --project-root "$TEST_PROJECT"
  chmod 644 "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unreadable_skipped: 1"* ]]
}
