#!/usr/bin/env bats

# Metadata-envelope + close-field block-reader tests (Release A of
# The plan, parser layer).
#
# The metadata envelope is the fence-stripped lines of a document before the first
# unfenced `##` heading; everything at or below that heading is narrative and never
# schema. One shared envelope reader (doc_lines_envelope in codeguide_doc_lines.sh)
# serves both the writer (doc_garden) and the validator; validate_docs.d/10-parse.sh
# wraps it in extract_field_block without re-implementing or re-sourcing it.

load codeguide_helper

# The same two-file stack the validator loads -- codeguide_doc_lines.sh first, then the
# parse module -- with extract_field_block invoked on a fixture. Runs in a fresh
# `bash -c` so no function or variable leaks between tests. FENCE_STRIP_CACHE is unset so
# the strip falls back to a per-call python spawn: correct output, and the cached path is
# covered deterministically by the performance test below.
read_block_field() {
  bash -c '
    unset FENCE_STRIP_CACHE
    source "$1"
    source "$2"
    extract_field_block "$3" "$4"
  ' _ "$SCRIPTS_DIR/codeguide_doc_lines.sh" "$SCRIPTS_DIR/validate_docs.d/10-parse.sh" "$1" "$2"
}

read_envelope() {
  bash -c 'source "$1"; doc_lines_envelope "$2"' _ "$SCRIPTS_DIR/codeguide_doc_lines.sh" "$1"
}

# --- envelope: shared reader (doc_lines_envelope) ---

@test "the envelope stops at the first unfenced ## heading" {
  local doc="$TEST_WORKSPACE/envelope-stop.md"
  cat > "$doc" <<'EOF'
# TASK-envelope-stop

- title: Envelope stop fixture
- status: planned
## Close-out
- outcome: below the envelope
EOF

  run read_envelope "$doc"
  [ "$status" -eq 0 ]
  assert_equal "$output" $'# TASK-envelope-stop\n\n- title: Envelope stop fixture\n- status: planned'
}

@test "a fenced ## heading does not end the envelope" {
  local doc="$TEST_WORKSPACE/envelope-fenced-heading.md"
  cat > "$doc" <<'EOF'
# TASK-envelope-fenced-heading

- title: Fenced heading fixture
```markdown
## Fenced heading
```
- status: planned
EOF

  run read_envelope "$doc"
  [ "$status" -eq 0 ]
  # The fenced ## is block content, so the envelope runs past the fence to the real
  # `- status:` line.
  assert_equal "$output" $'# TASK-envelope-fenced-heading\n\n- title: Fenced heading fixture\n- status: planned'
}

@test "fenced content is excluded from the envelope" {
  local doc="$TEST_WORKSPACE/envelope-fenced-content.md"
  cat > "$doc" <<'EOF'
# TASK-envelope-fenced-content

- title: Fenced content fixture
```markdown
- status: quoted
- owner: quoted
```
- status: planned
EOF

  run read_envelope "$doc"
  [ "$status" -eq 0 ]
  refute_contains "$output" "quoted"
  assert_equal "$output" $'# TASK-envelope-fenced-content\n\n- title: Fenced content fixture\n- status: planned'
}

@test "a - outcome: below ## Close-out is outside the envelope and reads as empty" {
  local doc="$TEST_WORKSPACE/close-out-outside-envelope.md"
  cat > "$doc" <<'EOF'
# TASK-close-out-outside-envelope

- title: Close-out outside the envelope
- status: done
## Close-out
- outcome: completed everything
EOF

  # The envelope itself stops before ## Close-out: neither the heading nor the
  # `- outcome:` value below it is in the envelope (the fixture title legitimately
  # mentions the section name above the boundary, so the needles are the heading syntax
  # and the below-boundary value).
  run read_envelope "$doc"
  [ "$status" -eq 0 ]
  refute_contains "$output" "## Close-out"
  refute_contains "$output" "completed everything"

  # The block reader wraps the SAME envelope, so a close field written below the
  # boundary is narrative and never satisfies the close-record gate.
  run read_block_field "$doc" "outcome"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

# --- block reader: extract_field_block ---

@test "extract_field_block reads an inline scalar" {
  local doc="$TEST_WORKSPACE/block-inline.md"
  cat > "$doc" <<'EOF'
# Capsule

- outcome: completed by 2026-08-16
- status: done
EOF

  run read_block_field "$doc" "outcome"
  [ "$status" -eq 0 ]
  assert_equal "$output" "completed by 2026-08-16"
}

@test "extract_field_block reads contiguous nested bullets as a filled value" {
  local doc="$TEST_WORKSPACE/block-nested.md"
  cat > "$doc" <<'EOF'
# Capsule

- outcome:
  - Evidence: commit abc123 merged
  - Summary: all release-A gates green
- status: done
EOF

  run read_block_field "$doc" "outcome"
  [ "$status" -eq 0 ]
  assert_equal "$output" $'  - Evidence: commit abc123 merged\n  - Summary: all release-A gates green'
}

@test "extract_field_block returns empty for fence-only content" {
  local doc="$TEST_WORKSPACE/block-fence-only.md"
  cat > "$doc" <<'EOF'
- outcome:
  ```text
  - quoted: this is inside a fence
  ```
- status: done
EOF

  run read_block_field "$doc" "outcome"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

@test "extract_field_block returns empty for a bare nested dash" {
  local doc="$TEST_WORKSPACE/block-dash-only.md"
  cat > "$doc" <<'EOF'
- outcome:
  -
- status: done
EOF

  run read_block_field "$doc" "outcome"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

@test "extract_field_block returns empty for a bare checkbox" {
  local doc="$TEST_WORKSPACE/block-checkbox-only.md"
  cat > "$doc" <<'EOF'
- outcome:
  - [ ]
- status: done
EOF

  run read_block_field "$doc" "outcome"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

@test "extract_field_block returns empty for whitespace-only content" {
  local doc="$TEST_WORKSPACE/block-blank-only.md"
  cat > "$doc" <<'EOF'
- outcome:
    
- status: done
EOF

  run read_block_field "$doc" "outcome"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

@test "extract_field_block returns empty for an HTML-comment-only block" {
  local doc="$TEST_WORKSPACE/block-comment-only.md"
  cat > "$doc" <<'EOF'
- outcome:
  <!-- outcome not recorded -->
- status: done
EOF

  run read_block_field "$doc" "outcome"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

@test "extract_field_block returns empty when the block is heading-only" {
  local doc="$TEST_WORKSPACE/block-heading-only.md"
  cat > "$doc" <<'EOF'
- outcome:
## Close-out
EOF

  run read_block_field "$doc" "outcome"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

@test "extract_field_block terminates at the next same-key occurrence" {
  local doc="$TEST_WORKSPACE/block-same-key.md"
  cat > "$doc" <<'EOF'
- outcome:
  - first attempt
- outcome:
  - second attempt
EOF

  run read_block_field "$doc" "outcome"
  [ "$status" -eq 0 ]
  assert_equal "$output" "  - first attempt"
}

@test "extract_field_block terminates at the next other-key occurrence" {
  local doc="$TEST_WORKSPACE/block-other-key.md"
  cat > "$doc" <<'EOF'
- outcome:
  - Evidence: abc
- status: done
EOF

  run read_block_field "$doc" "outcome"
  [ "$status" -eq 0 ]
  assert_equal "$output" "  - Evidence: abc"
}

@test "extract_field_block terminates at a blank line even inside nested bullets" {
  local doc="$TEST_WORKSPACE/block-blank-term.md"
  cat > "$doc" <<'EOF'
- outcome:
  - Evidence: abc

- status: done
EOF

  run read_block_field "$doc" "outcome"
  [ "$status" -eq 0 ]
  assert_equal "$output" "  - Evidence: abc"
}

@test "extract_field_block terminates at unindented prose" {
  local doc="$TEST_WORKSPACE/block-prose-term.md"
  cat > "$doc" <<'EOF'
- outcome:
  - Evidence: abc
unindented prose after the block
EOF

  run read_block_field "$doc" "outcome"
  [ "$status" -eq 0 ]
  assert_equal "$output" "  - Evidence: abc"
}

@test "extract_field_block takes the first duplicate occurrence" {
  local doc="$TEST_WORKSPACE/block-dup-inline.md"
  cat > "$doc" <<'EOF'
- outcome: first value
- outcome: second value
EOF

  run read_block_field "$doc" "outcome"
  [ "$status" -eq 0 ]
  assert_equal "$output" "first value"
}

@test "nested - key: lines are block content, never fields" {
  local doc="$TEST_WORKSPACE/block-nested-key.md"
  cat > "$doc" <<'EOF'
- outcome:
  - outcome: nested outcome is content
EOF

  run read_block_field "$doc" "outcome"
  [ "$status" -eq 0 ]
  assert_equal "$output" "  - outcome: nested outcome is content"
}

# --- performance: deterministic, no wall-clock bounds ---

@test "envelope reads from the pre-populated cache spawn zero python processes" {
  # Prepopulate the fence-strip cache exactly the way validate_docs.sh's corpus pre-strip
  # does, then put a FAIL-on-invocation python3 on PATH and read envelopes: any python
  # spawn is a cache miss, so zero invocations is the assertion.
  local doc="$TEST_WORKSPACE/capsule.md"
  local cache="$TEST_WORKSPACE/envelope-cache"
  local shim_dir="$TEST_WORKSPACE/py-shim"
  local log="$TEST_WORKSPACE/python3-argv.log"

  cat > "$doc" <<'EOF'
# Capsule

- outcome:
  - Evidence: cached block
- status: planned
EOF

  mkdir -p "$cache/$(dirname "${doc#/}")"
  python3 - "$doc" "$SCRIPTS_DIR" > "$cache/${doc#/}" <<'STRIPPY'
import sys
sys.path.insert(0, sys.argv[2])
sys.dont_write_bytecode = True
import shadow_doc_parse
lines = shadow_doc_parse.read_lines(sys.argv[1])
sys.stdout.write("\n".join(shadow_doc_parse.content_lines(lines)) + "\n")
STRIPPY

  mkdir -p "$shim_dir"
  cat > "$shim_dir/python3" <<SHIM
#!/bin/sh
printf '%s\n' "\$*" >> "$log"
echo "python3 invoked during a cached envelope read" >&2
exit 3
SHIM
  chmod +x "$shim_dir/python3"
  : > "$log"

  # extract_field_block wraps doc_lines_envelope on the cached stripped copy.
  run env PATH="$shim_dir:$PATH" FENCE_STRIP_CACHE="$cache" bash -c \
    "source '$SCRIPTS_DIR/codeguide_doc_lines.sh'; source '$SCRIPTS_DIR/validate_docs.d/10-parse.sh'; extract_field_block '$doc' outcome"
  [ "$status" -eq 0 ]
  assert_equal "$output" "  - Evidence: cached block"

  # The envelope reader alone (pure shell) also spawns nothing.
  : > "$log"
  run env PATH="$shim_dir:$PATH" FENCE_STRIP_CACHE="$cache" bash -c \
    "source '$SCRIPTS_DIR/codeguide_doc_lines.sh'; doc_lines_envelope '$doc'"
  [ "$status" -eq 0 ]
  # The binding assertion: zero python invocations on the cached envelope path.
  assert_equal "$(wc -l < "$log" | tr -d ' ')" "0"

  # Positive control for the counter: without the cache, the strip python spawn hits the
  # failing stub, so the log proves the shim would catch a cache miss.
  : > "$log"
  run env PATH="$shim_dir:$PATH" bash -c \
    "unset FENCE_STRIP_CACHE; source '$SCRIPTS_DIR/codeguide_doc_lines.sh'; source '$SCRIPTS_DIR/validate_docs.d/10-parse.sh'; extract_field_block '$doc' outcome"
  assert_contains "$(cat "$log")" "$doc"
}
