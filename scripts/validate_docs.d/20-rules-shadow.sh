#!/usr/bin/env bash
# validate_docs.d/20-rules-shadow.sh — Shadow rules: graph/schema/digest/nav-link checks plus the effect-map, review-queue, and policy/registry families.
# Sourced by validate_docs.sh after CLI/global setup; not executable alone.
# Split from validate_docs.sh (behavior-preserving; function bodies verbatim).

# list_has_line <newline-separated list> <exact line>: whole-line membership in pure bash.
# `printf '%s\n' "$list" | grep -Fxq "$line"` lets grep exit on the first hit while printf is
# still writing; under `set -o pipefail` the producer's SIGPIPE then fails the pipeline even
# though the line IS in the list, so a registry id was reported missing at random. A
# here-string would avoid the pipe, but bash 3.2 backs it with a temp file that ignores
# $TMPDIR (see check_effect_map_file), so this stays pipe-free and temp-file-free.
list_has_line() {
  case $'\n'"$1"$'\n' in
    *$'\n'"$2"$'\n'*) return 0 ;;
  esac
  return 1
}

# is_shadow_bucket <value>: exact membership in SHADOW_BUCKETS without piping the array anywhere.
is_shadow_bucket() {
  local bucket

  for bucket in "${SHADOW_BUCKETS[@]}"; do
    [[ "$bucket" == "$1" ]] && return 0
  done
  return 1
}

check_redirect_shim_file() {
  local file_path="$1"
  local label="$2"

  check_field_value_equals "$file_path" "doc_role" "redirect_shim" "$label" || true
  check_field_exists "$file_path" "legacy_path" "$label" || true
  check_field_exists "$file_path" "canonical_path" "$label" || true
  check_field_exists "$file_path" "redirects_fact_scope" "$label" || true
  check_field_exists "$file_path" "deprecated_since" "$label" || true
  check_field_value_equals "$file_path" "status" "redirected" "$label" || true
  check_field_value_equals "$file_path" "edit_policy" "read_only" "$label" || true
  check_field_exists "$file_path" "replacement_reason" "$label" || true
  check_field_exists "$file_path" "last_updated" "$label" || true
}

check_effect_map_file() {
  local file_path="$1"
  local issue_output

  check_field_value_equals "$file_path" "doc_role" "effect_map" "shadow effect_map" || true
  # Script body lives in a real file, not a heredoc: bash materializes a here-document
  # through its own temp-file mechanism, which ignores $TMPDIR and fails under a
  # sandboxed TMPDIR. `python3 - ARGS < file` keeps argv[0]/sys.path[0] identical.
  issue_output="$(python3 - "$file_path" "$POLICY_DIR" "$PROJECT_ROOT_ABS" "$SCRIPT_DIR" < "$SCRIPT_DIR/validate_docs_effect_map.py"
)"
  if [[ -n "$issue_output" ]]; then
    while IFS= read -r issue; do
      [[ -n "$issue" ]] && fail "${issue} in shadow effect_map: $file_path"
    done < <(printf '%s\n' "$issue_output")
  else
    pass "shadow effect_map records valid: $file_path"
  fi
}

check_review_queue_file() {
  local file_path="$1"
  local issue_output

  check_field_value_equals "$file_path" "doc_role" "review_queue" "shadow review_queue" || true
  check_field_non_empty "$file_path" "task_id" "shadow review_queue" || true
  check_field_value_equals "$file_path" "generated_by" "shadow_review_queue.py" "shadow review_queue" || true
  check_field_non_empty "$file_path" "generated_at" "shadow review_queue" || true
  check_field_non_empty "$file_path" "ttl_days" "shadow review_queue" || true
  check_field_value_equals "$file_path" "writes_shadow_docs" "false" "shadow review_queue" || true
  check_field_value_equals "$file_path" "auto_promotes_facts" "false" "shadow review_queue" || true

  # Script body lives in a real file, not a heredoc: bash materializes a here-document
  # through its own temp-file mechanism, which ignores $TMPDIR and fails under a
  # sandboxed TMPDIR. `python3 - ARGS < file` keeps argv[0]/sys.path[0] identical.
  issue_output="$(python3 - "$file_path" < "$SCRIPT_DIR/validate_docs_review_queue.py"
)"
  if [[ -n "$issue_output" ]]; then
    while IFS= read -r issue; do
      [[ -n "$issue" ]] && fail "${issue} in shadow review_queue: $file_path"
    done < <(printf '%s\n' "$issue_output")
  else
    pass "shadow review_queue source refs are bounded: $file_path"
  fi
}

# Content-based replacement for the removed timestamp heuristic (a shadow doc
# "older than" the newest task/decision doc): garden no longer blind-bumps
# bucket/_global docs and only bumps the router on a real change, so a
# last_updated-vs-last_updated comparison would just measure which script ran
# most recently, not whether the shadow graph documents anything. What DOES
# matter is a shadow graph that is entirely EMPTY -- no unit anywhere, no
# source_of_truth_paths declared anywhere -- while the project has real source
# to document. Fires only when a source repo is actually reachable and has
# git-tracked files outside docs/; a scaffold-only fixture with no source repo
# must never trip it.
check_shadow_empty_graph() {
  local source_root
  local bucket
  local bucket_file
  local any_units="false"
  local has_source="false"
  local tracked_path

  source_root="$(codeguide_source_root "$PROJECT_ROOT_ABS" 2>/dev/null || true)"
  [[ -n "$source_root" ]] || return 0

  # Scaffold artifacts are not "source needing documentation": a freshly
  # bootstrapped docs-only project tracks its routers and markers but no code
  # (fable/sonnet P3-r01 shared finding — the gate must not fail it).
  # The listing is read by a loop that stops at the first real source path, not piped into
  # `grep -q`: grep exited at that path while `git ls-files` was still writing, and under
  # pipefail the SIGPIPE read as "no source", so a repository whose listing outgrew the pipe
  # buffer skipped this gate and strict validation passed an empty shadow graph.
  while IFS= read -r tracked_path; do
    case "$tracked_path" in
      docs/*|AGENTS.md|CLAUDE.md|README.md|.gitignore|.codeguide-source-root) ;;
      *)
        has_source="true"
        break
        ;;
    esac
  done < <(git -C "$source_root" ls-files 2>/dev/null)
  [[ "$has_source" == "true" ]] || return 0

  [[ -d "$SHADOW_DIR" ]] || return 0

  for bucket in "${SHADOW_BUCKETS[@]}"; do
    bucket_file="$SHADOW_DIR/$bucket/_index.md"
    [[ -f "$bucket_file" ]] || continue
    if bucket_index_has_units "$bucket_file"; then
      any_units="true"
      break
    fi
  done

  if [[ "$any_units" == "true" ]]; then
    pass "shadow graph is not empty: at least one bucket declares a unit"
    return 0
  fi

  if shadow_tree_has_source_declarations; then
    pass "shadow graph is not empty: at least one shadow doc declares source_of_truth_paths"
    return 0
  fi

  fail "shadow graph is empty: no bucket declares a unit and no shadow doc declares source_of_truth_paths, though the source repo has trackable files to document. Author shadow units; see shadow_coverage_report.py for the coverage gap"
}

# True if the bucket index's "## Units" section lists a real unit entry. The
# schema shape is "- <unit_id>:" (identifier then colon) with indented detail
# lines; an arbitrary garbage line like "- x" must not be able to silence the
# empty-graph gate (sonnet P3-r01 finding 2).
#
# Reads the fence-stripped copy, for the same reason the sibling
# shadow_tree_has_source_declarations below is fence-aware: this is the OTHER half of
# check_shadow_empty_graph, and while it was fence-blind the two halves answered one gate
# with two grammars. Wrapping a single example unit row in a fence turned the strict
# `[FAIL] shadow graph is empty` into `[PASS] shadow graph is not empty` -- a quoted
# template silencing an enforcement gate on a corpus that documents nothing
# (the task r02 finding 3, reproduced on a fixture with a real
# git source root; a bare scaffold cannot show it because the gate returns early with no
# trackable source).
bucket_index_has_units() {
  local bucket_file="$1"
  local remaining

  fence_stripped_file "$bucket_file"
  remaining="$(awk '/^## Units$/{flag=1; next} /^## /{flag=0} flag && /^- /{print}' "$FENCE_STRIPPED_PATH" 2>/dev/null \
    | grep -vFx -- '- no units detected yet' \
    | grep -E '^- [A-Za-z0-9._-]+:' || true)"
  [[ -n "$remaining" ]]
}

# True if ANY shadow doc (excluding _deprecated/_obsolete) declares at least
# one real source_of_truth_paths entry. Reuses shadow_source_digest.py's
# fence-aware parser (the same one check_shadow_source_paths_exist trusts) so
# a fenced-code-block mention of the field cannot manufacture coverage.
shadow_tree_has_source_declarations() {
  local digest_helper="$SCRIPT_DIR/shadow_source_digest.py"
  local shadow_doc
  local result
  local has_paths

  [[ -f "$digest_helper" ]] || return 1
  [[ -d "$SHADOW_DIR" ]] || return 1

  while IFS= read -r shadow_doc; do
    grep -qE "source_of_truth_paths" "$shadow_doc" 2>/dev/null || continue
    result="$(python3 "$digest_helper" "$shadow_doc" --project-root "$PROJECT_ROOT_ABS" --verify-paths 2>/dev/null || true)"
    has_paths="$(printf "%s\n" "$result" | sed -n 's/^has_paths: //p' | sed -n '1p')"
    if [[ "$has_paths" == "true" ]]; then
      return 0
    fi
  done < <(
    find "$SHADOW_DIR" -type f -name '*.md' \
      ! -path "$SHADOW_DIR/_deprecated/*" \
      ! -path "$SHADOW_DIR/_obsolete/*" \
      | sort
  )
  return 1
}

# Advisory-only (recommended tier): every navigation reference in a shadow doc
# that names a Markdown target must resolve to a real file. This catches a
# rotting read path (dangling overview_doc/next_docs/bucket_links/global_doc, or a
# redirect shim whose canonical_path no longer exists) without breaking existing
# corpora, so it is guarded to advisory mode by the caller (same tier as
# owner/claimed_at). Only values that end in .md are resolved, which excludes tags,
# prose, ids, and source_of_truth code paths (those are covered by other checks).
check_shadow_navigation_links() {
  local issue_output

  # Script body lives in a real file, not a heredoc: bash materializes a here-document
  # through its own temp-file mechanism, which ignores $TMPDIR and fails under a
  # sandboxed TMPDIR. `python3 - ARGS < file` keeps argv[0]/sys.path[0] identical.
  issue_output="$(python3 - "$SHADOW_DIR" "$PROJECT_ROOT_ABS" "$DOCS_DIR" "$SCRIPT_DIR" < "$SCRIPT_DIR/validate_docs_nav_links.py"
)"

  if [[ -n "$issue_output" ]]; then
    while IFS=$'\t' read -r ref_file field token; do
      [[ -n "$ref_file" ]] && fail "shadow navigation reference does not resolve: ${field} -> ${token} (${ref_file}); fix the link or remove the stale reference"
    done < <(printf '%s\n' "$issue_output")
  else
    pass "shadow navigation references resolve to real files"
  fi
}

# Advisory-only (recommended tier): for any shadow doc that has opted in by carrying
# a source_of_truth_digest, recompute the digest of its declared source_of_truth_paths
# and warn on drift or a missing declared source. This binds freshness to source
# CONTENT (not a timestamp that doc_garden auto-bumps). The digest algorithm lives in
# scripts/shadow_source_digest.py; this only consumes its --check result.
check_shadow_source_digest() {
  local digest_helper="$SCRIPT_DIR/shadow_source_digest.py"
  if [[ ! -f "$digest_helper" ]]; then
    return 0
  fi
  local checked=0
  local problems=0
  local shadow_doc
  local result
  local rc
  local line
  local status_line
  while IFS= read -r shadow_doc; do
    # Cheap fence-BLIND prefilter: it only decides which documents are worth a python
    # spawn. `checked` is NOT set here, because that made the prefilter the reader --
    # a document merely QUOTING the field inside a fenced example manufactured
    # "shadow source-of-truth digests verified against current source" on a corpus where
    # the fence-aware helper says no_digest and nothing is verified at all
    # The helper decides.
    grep -qE "^[[:space:]]*-[[:space:]]*source_of_truth_digest:" "$shadow_doc" 2>/dev/null || continue
    # `if !` keeps a helper crash from aborting the whole run under `set -e`.
    if ! result="$(python3 "$digest_helper" "$shadow_doc" --project-root "$PROJECT_ROOT_ABS" --check 2>/dev/null)"; then
      fail "could not verify shadow source-of-truth digest (helper error): $shadow_doc"
      problems=1
      continue
    fi
    status_line=""
    while IFS= read -r line; do
      case "$line" in
        "status: "*) status_line="${line#status: }" ;;
        "missing: "*)
          fail "shadow source-of-truth declared path does not exist: ${line#missing: } ($shadow_doc)"
          problems=1
          ;;
        "escaped: "*)
          fail "shadow source-of-truth declared path escapes the project root: ${line#escaped: } ($shadow_doc)"
          problems=1
          ;;
      esac
    done < <(printf '%s\n' "$result")
    if [[ -z "$status_line" ]]; then
      fail "could not verify shadow source-of-truth digest (helper error): $shadow_doc"
      problems=1
      continue
    fi
    case "$status_line" in
      no_digest)
        # The only mention of the field was inside a fence, so this document declares
        # nothing and must not count toward the PASS below.
        continue
        ;;
      drift)
        fail "shadow source-of-truth digest drift, source changed since last verification: $shadow_doc; re-verify then rerun scripts/shadow_source_digest.py --write"
        problems=1
        ;;
      no_paths)
        fail "shadow source_of_truth_digest present but no source_of_truth_paths declared: $shadow_doc"
        problems=1
        ;;
    esac
    checked=1
  done < <(
    find "$SHADOW_DIR" -type f -name '*.md' \
      ! -path "$SHADOW_DIR/_deprecated/*" \
      ! -path "$SHADOW_DIR/_obsolete/*" \
      | sort
  )
  if (( checked == 1 && problems == 0 )); then
    pass "shadow source-of-truth digests verified against current source"
  fi
}

# Advisory-only (recommended tier): every source_of_truth_paths entry must resolve to
# a real in-project file. This catches a dead/renamed/typo source pointer even when the
# doc has not opted into a source_of_truth_digest. Docs that DO carry a digest are
# skipped here because check_shadow_source_digest already reports their missing/escaped
# sources; this avoids duplicate warnings.
check_shadow_source_paths_exist() {
  local digest_helper="$SCRIPT_DIR/shadow_source_digest.py"
  if [[ ! -f "$digest_helper" ]]; then
    return 0
  fi
  local checked=0
  local problems=0
  local shadow_doc
  local result
  local line
  local has_paths
  local has_digest
  while IFS= read -r shadow_doc; do
    # Cheap pre-filter only; the skip/report decision below is parser-backed.
    grep -qE "source_of_truth_paths" "$shadow_doc" 2>/dev/null || continue
    # `if !` keeps a helper crash from aborting the whole run under `set -e`.
    if ! result="$(python3 "$digest_helper" "$shadow_doc" --project-root "$PROJECT_ROOT_ABS" --verify-paths 2>/dev/null)"; then
      fail "could not verify shadow source_of_truth_paths (helper error): $shadow_doc"
      problems=1
      continue
    fi
    has_paths=""
    has_digest=""
    while IFS= read -r line; do
      case "$line" in
        "has_paths: "*) has_paths="${line#has_paths: }" ;;
        "has_digest: "*) has_digest="${line#has_digest: }" ;;
      esac
    done < <(printf '%s\n' "$result")
    # Parser-backed gating: skip docs with no real declared paths, and docs that carry
    # a real digest (check_shadow_source_digest owns those). Deciding this from the
    # fence-aware parser rather than a raw grep closes the empty/fenced-field evasion
    # where a bare or fenced source_of_truth_digest line silenced this check.
    [[ "$has_paths" == "true" ]] || continue
    [[ "$has_digest" == "true" ]] && continue
    checked=1
    while IFS= read -r line; do
      case "$line" in
        "missing: "*)
          fail "shadow source_of_truth path does not exist: ${line#missing: } ($shadow_doc)"
          problems=1
          ;;
        "escaped: "*)
          fail "shadow source_of_truth path escapes the project root: ${line#escaped: } ($shadow_doc)"
          problems=1
          ;;
      esac
    done < <(printf '%s\n' "$result")
  done < <(
    find "$SHADOW_DIR" -type f -name '*.md' \
      ! -path "$SHADOW_DIR/_deprecated/*" \
      ! -path "$SHADOW_DIR/_obsolete/*" \
      | sort
  )
  if (( checked == 1 && problems == 0 )); then
    pass "shadow source_of_truth_paths all resolve to real in-project files"
  fi
}

# Fence-aware reader for a top-level "- key:" field: returns the first non-empty value
# that is NOT inside a fenced code example, tolerating leading indentation. This avoids
# treating a fenced template example as a real field, surfaces indented carriers instead
# of silently skipping them, and skips an empty stub in favour of a later real value.
extract_shadow_field() {
  local file_path="$1"
  local key="$2"
  # Delegates to the shared reader so this and every other shadow rule answer
  # "is this line inside a fence" identically.
  # The awk it replaced toggled on any marker, so a ~~~ inside a ``` block flipped
  # the state; the shared reader closes only on a same-character marker.
  # Script body lives in a real file, not a heredoc: bash materializes a here-document
  # through its own temp-file mechanism, which ignores $TMPDIR and fails under a
  # sandboxed TMPDIR. `python3 - ARGS < file` keeps argv[0]/sys.path[0] identical.
  python3 - "$file_path" "$key" "$SCRIPT_DIR" < "$SCRIPT_DIR/validate_docs_shadow_field.py" 2>/dev/null
}

# Advisory-only (recommended tier): the shadow value-carrier docs (unit_overview,
# concern_leaf) have no field validation elsewhere -- only the line-limit and effect_map
# checks touch them. Verify the minimal IDENTIFYING schema (home_bucket / concern_id) so a
# malformed carrier is surfaced, without enforcing optional fields like last_updated
# (which has a documented mtime fallback elsewhere). Other doc_roles keep their own checks.
check_shadow_unit_schema() {
  local shadow_doc
  local doc_role
  local bucket_value
  local checked=0
  local problems=0
  while IFS= read -r shadow_doc; do
    doc_role="$(extract_shadow_field "$shadow_doc" "doc_role")"
    case "$doc_role" in
      unit_overview)
        checked=1
        bucket_value="$(extract_shadow_field "$shadow_doc" "home_bucket")"
        if [[ -z "$bucket_value" ]]; then
          fail "shadow unit overview missing home_bucket: $shadow_doc"
          problems=1
        elif ! is_shadow_bucket "$bucket_value"; then
          fail "shadow unit overview home_bucket is not a known bucket (${bucket_value}): $shadow_doc"
          problems=1
        fi
        ;;
      concern_leaf)
        checked=1
        if [[ -z "$(extract_shadow_field "$shadow_doc" "concern_id")" ]]; then
          fail "shadow concern leaf missing concern_id: $shadow_doc"
          problems=1
        fi
        ;;
    esac
  done < <(
    find "$SHADOW_DIR" -type f -name '*.md' \
      ! -path "$SHADOW_DIR/_deprecated/*" \
      ! -path "$SHADOW_DIR/_obsolete/*" \
      | sort
  )
  if (( checked == 1 && problems == 0 )); then
    pass "shadow unit/concern docs have valid schema"
  fi
}

# Advisory-only (recommended tier, gated by the caller): hop-2 unit selection.
# A bucket-index unit row must carry a `selection_summary` -- one line an agent
# reads to decide whether opening that unit's overview is worth it -- and it must
# be a byte-PREFIX of the overview's `unit_summary`. The prefix is the whole point:
# it binds the row to a doc one hop deeper that has to stay true, so drift on
# either side is detectable without a vocabulary or a tokenizer. This replaced
# `secondary_tags`, which nothing read and whose three live pairs had all silently
# diverged.
check_shadow_selection_summary() {
  local issue_output

  # Script body lives in a real file, not a heredoc: bash materializes a here-document
  # through its own temp-file mechanism, which ignores $TMPDIR and fails under a
  # sandboxed TMPDIR. `python3 - ARGS < file` keeps argv[0]/sys.path[0] identical.
  issue_output="$(python3 - "$SHADOW_DIR" "$SCRIPT_DIR" < "$SCRIPT_DIR/validate_docs_selection_summary.py"
)"

  local index_file
  local unit
  local kind
  local detail
  local problems=0

  if [[ -n "$issue_output" ]]; then
    while IFS=$'\t' read -r index_file unit kind detail; do
      [[ -n "$index_file" ]] || continue
      case "$kind" in
        missing)
          fail "shadow bucket unit is missing selection_summary (${unit}): $index_file"
          ;;
        no_overview)
          fail "shadow bucket unit row has no overview_doc (${unit}): $index_file"
          ;;
        multiline)
          fail "shadow selection_summary must be a single line (${unit}): $index_file"
          ;;
        too_short)
          fail "shadow selection_summary is too short to select anything (${unit}, ${detail} chars): $index_file"
          ;;
        too_long)
          fail "shadow selection_summary exceeds 250 characters (${unit}, ${detail}): $index_file"
          ;;
        no_summary)
          fail "shadow selection_summary target overview has no unit_summary (${unit} -> ${detail}): $index_file"
          ;;
        not_prefix)
          fail "shadow selection_summary is not a prefix of the overview unit_summary (${unit} -> ${detail}); the row and the overview opening have drifted apart: $index_file"
          ;;
      esac
      problems=1
    done < <(printf '%s\n' "$issue_output")
  fi

  # The replaced field must not creep back in: nothing reads it, and its three
  # live pairs had already diverged when it was removed.
  # Fence-aware, and blind to the archive trees: a doc quoting the old contract in a
  # fenced example is not a regression, and _deprecated/_obsolete bodies are frozen
  # history that must not be rewritten to satisfy a new field.
  local stale_tags
  # Script body lives in a real file, not a heredoc: bash materializes a here-document
  # through its own temp-file mechanism, which ignores $TMPDIR and fails under a
  # sandboxed TMPDIR. `python3 - ARGS < file` keeps argv[0]/sys.path[0] identical.
  stale_tags="$(python3 - "$SHADOW_DIR" "$SCRIPT_DIR" < "$SCRIPT_DIR/validate_docs_selection_stale_tags.py"
)"
  if [[ -n "$stale_tags" ]]; then
    while IFS= read -r stale_file; do
      [[ -n "$stale_file" ]] && fail "shadow doc still declares the removed secondary_tags field; use selection_summary on the bucket row instead: $stale_file"
    done < <(printf '%s\n' "$stale_tags")
    problems=1
  fi

  if (( problems == 0 )); then
    pass "shadow bucket rows carry a selection_summary that prefixes their unit overview"
  fi
}

# Advisory-only (recommended tier, gated by the caller like the navigation-link
# check): `linked_decisions` is the authored rationale edge -- the "why does this
# code exist" hop of the read path.
#
# The grammar lives in ONE place: shadow_rationale_report.py --lint owns parsing
# (fences, the inline-comma-list rule, entry shape, target status) and this rule
# owns tiering and message text. Two hand-written parsers were tried first and
# drifted on the trailing-empty-member and fenced-example cases within a day --
# same lesson, and same fix, as check_shadow_source_digest delegating to
# shadow_source_digest.py --check.
check_shadow_linked_decisions() {
  local helper="$SCRIPT_DIR/shadow_rationale_report.py"
  local lint_output
  local kind
  local doc
  local detail
  local problems=0
  local declared_count=0

  [[ -f "$helper" ]] || return 0

  # `if !` keeps a helper crash from aborting the whole run under `set -e`.
  if ! lint_output="$(python3 "$helper" --project-root "$PROJECT_ROOT_ABS" --lint 2>/dev/null)"; then
    fail "could not lint shadow linked_decisions (helper error): $helper"
    return 0
  fi

  while IFS=$'\t' read -r kind doc detail; do
    [[ -n "$kind" ]] || continue
    case "$kind" in
      declared)
        # Count is the second field: TAB is IFS whitespace, so an empty middle
        # field would collapse and shift the value (see the helper's --lint note).
        declared_count="$doc"
        ;;
      nested)
        fail "shadow linked_decisions must be an inline comma list, not nested bullets: $doc"
        problems=1
        ;;
      role)
        fail "shadow linked_decisions is only valid on unit_overview or concern_leaf (doc_role=${detail}): $doc"
        problems=1
        ;;
      empty)
        fail "shadow linked_decisions has an empty member: $doc"
        problems=1
        ;;
      duplicate)
        fail "shadow linked_decisions lists a duplicate decision (${detail}): $doc"
        problems=1
        ;;
      not_capsule)
        fail "shadow linked_decisions must name a decision capsule, not the index (${detail}): $doc"
        problems=1
        ;;
      shape)
        fail "shadow linked_decisions entry must be a repo-relative docs/decisions/decision-<id>.md path (${detail}): $doc"
        problems=1
        ;;
      dangling)
        fail "shadow linked_decisions reference does not resolve (${detail}): $doc"
        problems=1
        ;;
      superseded)
        fail "shadow linked_decisions points at a superseded decision (${detail}); link the successor: $doc"
        problems=1
        ;;
      proposed)
        # Non-blocking in both modes: linking a proposal is legitimate while it
        # is being decided, but it must not read as settled rationale.
        soft_warn "shadow linked_decisions points at a proposed decision (${detail}): $doc"
        ;;
      no_status)
        fail "shadow linked_decisions target has no readable status (${detail}): $doc"
        problems=1
        ;;
    esac
  done < <(printf '%s\n' "$lint_output")

  # A corpus with no rationale at all is not a finding; only report the clean
  # state when the field is actually in use (count comes from the same parser,
  # so a fenced example can never be mistaken for a real declaration).
  if (( problems == 0 )) && (( declared_count > 0 )); then
    pass "shadow linked_decisions resolve to operative decision capsules"
  fi
}

# Advisory-only, and additionally gated on an adoption signal: a policy registry
# still carrying only its shipped `template_linked_*` placeholder is unadopted,
# not broken. Warning about it in a project that has no decisions yet would tell
# the author to link a capsule that cannot exist. Once the project has written
# even one decision capsule, an unfilled placeholder IS rot worth naming -- this
# repo carried three dangling placeholder targets unnoticed for months because
# presence-only checking accepted them.
#
# MODE is checked in the body, not by the caller: unlike the shadow-graph checks,
# check_shadow_policy_files runs in BOTH modes, so an ungated fail here would put
# new findings into strict.
check_policy_decision_links() {
  local policy_file="$1"
  local label="$2"
  local singular_key="$3"
  local plural_key="$4"
  local raw_value
  local entry
  local key
  local concrete_values
  local has_placeholder
  local target_id
  local -a entries

  [[ "$MODE" != "strict" ]] || return 0
  [[ -f "$policy_file" ]] || return 0

  # Both concrete forms are validated when both exist: preferring one silently
  # would let a dangling value hide behind a healthy sibling field.
  concrete_values=""
  for key in "$singular_key" "$plural_key"; do
    raw_value="$(extract_field_value "$policy_file" "$key")"
    [[ -n "$raw_value" ]] || continue
    concrete_values="${concrete_values}${concrete_values:+,}${raw_value}"
  done

  if [[ -z "$concrete_values" ]]; then
    # No concrete link at all. Only nudge where the placeholder is actually still
    # in place AND adoption is possible (a project with at least one real capsule);
    # otherwise a fresh scaffold would be told to link something that cannot exist.
    has_placeholder=""
    for key in "template_${singular_key}" "template_${plural_key}"; do
      if [[ -n "$(extract_field_value "$policy_file" "$key")" ]]; then
        has_placeholder="yes"
        break
      fi
    done
    [[ -n "$has_placeholder" ]] || return 0
    if [[ -n "$(find "$DECISIONS_DIR" -maxdepth 1 -type f -name 'decision-*.md' ! -name 'decision-index.md' ! -name 'decision-template.md' 2>/dev/null | head -n 1)" ]]; then
      fail "${label} still carries only the shipped template_${singular_key} placeholder: replace it with a real ${singular_key} now that this project has decision capsules ($policy_file)"
    fi
    return 0
  fi

  entries=()
  IFS=',' read -r -a entries < <(printf '%s\n' "$concrete_values")
  for entry in "${entries[@]}"; do
    entry="$(printf '%s' "$entry" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -n "$entry" ]] || continue
    target_id="${entry##*/}"
    target_id="${target_id%.md}"
    if [[ ! -f "$DECISIONS_DIR/${target_id}.md" ]]; then
      fail "${label} ${singular_key} does not resolve to a decision capsule (${entry}): expected $DECISIONS_DIR/${target_id}.md"
    fi
  done
}

check_shadow_router_task_link() {
  local router_file="$SHADOW_DIR/project-shadow.md"
  local task_value

  [[ -f "$router_file" ]] || return 0
  task_value="$(extract_field_value "$router_file" "updated_by_task")"
  [[ -n "$task_value" ]] || return 0

  # Shape first, existence second: without the anchored pattern, a value carrying
  # a trailing note ("TASK-x (done)") or a path fragment would either be looked up
  # as a nonsense filename or, worse, resolve outside docs/task via `../`.
  if [[ ! "$task_value" =~ ^TASK-[A-Za-z0-9._-]+$ ]]; then
    fail "shadow router updated_by_task must be a bare TASK-<id> value (${task_value}): $router_file"
    return 0
  fi

  if [[ -f "$TASK_DIR/${task_value}.md" ]]; then
    pass "shadow router updated_by_task resolves to a real task"
  else
    fail "shadow router updated_by_task does not resolve to a task file (${task_value}): expected $TASK_DIR/${task_value}.md"
  fi
}

collect_versioned_registry_ids() {
  local file_path="$1"
  grep -E '^[[:space:]]{2,}[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+@v[0-9]+:' "$file_path" 2>/dev/null \
    | sed -E 's/^[[:space:]]*([^:]+):.*$/\1/' \
    | sort -u || true
}

collect_versioned_registry_ids_in_block() {
  local file_path="$1"
  local block_name="$2"
  awk -v block_name="$block_name" '
    $0 == block_name ":" {
      in_block=1
      next
    }
    in_block && /^```/ {
      in_block=0
      next
    }
    in_block && /^[^[:space:]`#][^:]*:/ && $0 != block_name ":" {
      in_block=0
      next
    }
    in_block && /^[[:space:]]{2,}[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+@v[0-9]+:/ {
      id=$1
      sub(/:$/, "", id)
      print id
    }
  ' "$file_path" | sort -u || true
}

collect_rule_registry_refs() {
  local file_path="$1"
  local key="$2"
  grep -E "^[[:space:]]+${key}:[[:space:]]*[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+@v[0-9]+" "$file_path" 2>/dev/null \
    | sed -E "s/^[[:space:]]+${key}:[[:space:]]*([^ #]+).*$/\1/" \
    | sort -u || true
}

collect_backtick_registry_ids_for_field() {
  local file_path="$1"
  local field_name="$2"
  grep -E "^[[:space:]]*-[[:space:]]*${field_name}:" "$file_path" 2>/dev/null \
    | grep -oE '`[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+@v[0-9]+`' \
    | tr -d '`' \
    | sort -u || true
}

collect_probe_primary_validator_ids() {
  local probe_script="$1"
  python3 "$SCRIPT_DIR/shadow_policy_loader.py" --adapter-module "$probe_script" --print-adapter-ids 2>/dev/null || true
}

collect_policy_loader_ids() {
  local field_name="$1"
  set +e
  python3 "$SCRIPT_DIR/shadow_policy_loader.py" --policy-dir "$POLICY_DIR" --print-policy-json 2>/dev/null \
    | python3 -c 'import json,sys
field=sys.argv[1]
try:
    data=json.load(sys.stdin)
except Exception:
    data={}
value=data.get(field)
if isinstance(value, dict):
    items=sorted(value.keys())
elif isinstance(value, list):
    items=sorted(str(item) for item in value)
else:
    items=[]
for item in items:
    print(item)
' "$field_name"
  local status=$?
  set -e
  return "$status"
}

check_policy_loader_contract() {
  local loader_output
  local loader_status
  local issue_output

  set +e
  loader_output="$(python3 "$SCRIPT_DIR/shadow_policy_loader.py" --policy-dir "$POLICY_DIR" --adapter-module "$SCRIPT_DIR/shadow_evidence_probe.py" --check-parity 2>&1)"
  loader_status=$?
  set -e
  if (( loader_status == 0 )); then
    pass "shadow policy loader strict contract passes"
    return
  fi

  issue_output="$(printf "%s" "$loader_output" | python3 -c 'import json,sys
raw=sys.stdin.read()
try:
    data=json.loads(raw)
    errors=data.get("errors") or [data.get("error") or raw]
except Exception:
    errors=[raw]
for item in errors:
    print(item)
' 2>/dev/null || printf "%s\n" "$loader_output")"
  while IFS= read -r issue; do
    [[ -n "$issue" ]] && fail "shadow policy loader strict contract failed: ${issue}"
  done < <(printf '%s\n' "$issue_output")
}

check_catalog_probe_coverage() {
  local catalog_file="$1"
  local implemented_ids
  local parser_ids
  local source_probe_ids
  local declared_ids
  local probe_ids
  local id
  local mismatch_count=0

  declared_ids="$(collect_policy_loader_ids "validators")"
  implemented_ids="$(collect_policy_loader_ids "implemented_primary")"
  parser_ids="$(collect_policy_loader_ids "parser_backed_now")"
  source_probe_ids="$(collect_policy_loader_ids "source_probe_only")"
  probe_ids="$(collect_probe_primary_validator_ids "$SCRIPT_DIR/shadow_evidence_probe.py")"

  if [[ -z "$implemented_ids" ]]; then
    fail "shadow validator catalog must declare implemented_primary_v1 (${catalog_file})"
  else
    pass "shadow validator catalog declares implemented_primary_v1"
  fi
  if [[ -z "$parser_ids" ]]; then
    fail "shadow validator catalog must declare parser_backed_now (${catalog_file})"
  else
    pass "shadow validator catalog declares parser_backed_now"
  fi
  if [[ -z "$source_probe_ids" ]]; then
    fail "shadow validator catalog must declare source_probe_only (${catalog_file})"
  else
    pass "shadow validator catalog declares source_probe_only"
  fi
  if [[ -z "$probe_ids" ]]; then
    fail "shadow_evidence_probe.py must expose primary AdapterRegistry ids (${catalog_file})"
    mismatch_count=$((mismatch_count + 1))
  fi

  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if ! list_has_line "$declared_ids" "$id"; then
      fail "implemented_primary_v1 id must be declared in validators block: ${id} (${catalog_file})"
      mismatch_count=$((mismatch_count + 1))
    fi
    if [[ -n "$probe_ids" ]] && ! list_has_line "$probe_ids" "$id"; then
      fail "implemented_primary_v1 id must be implemented by shadow_evidence_probe.py: ${id} (${catalog_file})"
      mismatch_count=$((mismatch_count + 1))
    fi
  done < <(printf '%s\n' "$implemented_ids")

  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if ! list_has_line "$implemented_ids" "$id"; then
      fail "shadow_evidence_probe.py primary validator missing from implemented_primary_v1: ${id} (${catalog_file})"
      mismatch_count=$((mismatch_count + 1))
    fi
  done < <(printf '%s\n' "$probe_ids")

  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if ! list_has_line "$declared_ids" "$id"; then
      fail "parser_backed_now id must be declared in validators block: ${id} (${catalog_file})"
      mismatch_count=$((mismatch_count + 1))
    fi
    if ! list_has_line "$implemented_ids" "$id"; then
      fail "parser_backed_now id must also be implemented_primary_v1: ${id} (${catalog_file})"
      mismatch_count=$((mismatch_count + 1))
    fi
  done < <(printf '%s\n' "$parser_ids")

  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if ! list_has_line "$declared_ids" "$id"; then
      fail "source_probe_only id must be declared in validators block: ${id} (${catalog_file})"
      mismatch_count=$((mismatch_count + 1))
    fi
    if ! list_has_line "$implemented_ids" "$id"; then
      fail "source_probe_only id must also be implemented_primary_v1: ${id} (${catalog_file})"
      mismatch_count=$((mismatch_count + 1))
    fi
    if list_has_line "$parser_ids" "$id"; then
      fail "source_probe_only id must not also be parser_backed_now: ${id} (${catalog_file})"
      mismatch_count=$((mismatch_count + 1))
    fi
  done < <(printf '%s\n' "$source_probe_ids")

  if (( mismatch_count == 0 )); then
    pass "shadow validator catalog probe coverage sets are internally consistent"
  fi
}

check_rule_registry_ref_versions() {
  local rule_file="$1"
  local line
  local key
  local ref
  local invalid_count=0

  while IFS= read -r line; do
    key="$(printf "%s" "$line" | sed -E 's/^[[:space:]]+(primary|fallback):.*$/\1/')"
    ref="$(printf "%s" "$line" | sed -E 's/^[[:space:]]+(primary|fallback):[[:space:]]*([^ #]+).*$/\2/')"
    if [[ ! "$ref" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+@v[0-9]+$ ]]; then
      fail "rule registry ${key} reference must be versioned: ${ref} (${rule_file})"
      invalid_count=$((invalid_count + 1))
    fi
  done < <(grep -E '^[[:space:]]+(primary|fallback):' "$rule_file" 2>/dev/null || true)

  if (( invalid_count == 0 )); then
    pass "rule registry primary/fallback references are versioned"
  fi
}

check_policy_risk_field_values() {
  local file_path="$1"
  local field_name="$2"
  local label="$3"
  local line
  local value
  local seen_count=0
  local invalid_count=0

  while IFS= read -r line; do
    seen_count=$((seen_count + 1))
    value="$(printf "%s" "$line" | sed -E "s/^[[:space:]]+${field_name}:[[:space:]]*([^ #]+).*$/\1/")"
    if [[ ! "$value" =~ ^(low|medium)$ ]]; then
      fail "${field_name} must be low|medium in ${label}: ${value} (${file_path})"
      invalid_count=$((invalid_count + 1))
    fi
  done < <(grep -E "^[[:space:]]+${field_name}:" "$file_path" 2>/dev/null || true)

  if (( seen_count == 0 )); then
    fail "${field_name} is missing in ${label}: ${file_path}"
    return
  fi

  if (( invalid_count == 0 )); then
    pass "${field_name} values are low|medium in ${label}"
  fi
}

collect_validator_evidence_map() {
  local file_path="$1"
  awk '
    /^[[:space:]]{2,}[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+@v[0-9]+:/ {
      id=$1
      sub(/:$/, "", id)
      current=id
      next
    }
    current != "" && /^[[:space:]]+evidence_type:[[:space:]]*/ {
      evidence=$0
      sub(/^[[:space:]]+evidence_type:[[:space:]]*/, "", evidence)
      sub(/[[:space:]#].*$/, "", evidence)
      print current " " evidence
      current=""
    }
  ' "$file_path"
}

collect_regex_evidence_map() {
  local file_path="$1"
  awk '
    /^[[:space:]]{2,}[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+@v[0-9]+:/ {
      id=$1
      sub(/:$/, "", id)
      current=id
      next
    }
    current != "" && /^[[:space:]]+(target|evidence_type):[[:space:]]*/ {
      evidence=$0
      sub(/^[[:space:]]+(target|evidence_type):[[:space:]]*/, "", evidence)
      sub(/[[:space:]#].*$/, "", evidence)
      print current " " evidence
      current=""
    }
  ' "$file_path"
}

check_rule_registry_promotion_gates() {
  local rule_file="$1"
  local failures

  failures="$(awk '
    function mark_list(value) {
      if (value == "parser_backed_validator") parser=1
      if (value == "test_assertion") test=1
      if (value == "runtime_trace") runtime=1
      if (value == "valid_waiver") waiver=1
    }
    /^promotion_gates:[[:space:]]*$/ {
      in_pg=1
      section=""
      seen_pg=1
      next
    }
    in_pg && /^```/ {
      in_pg=0
      section=""
      next
    }
    in_pg && /^[^[:space:]][^:]*:[[:space:]]*$/ && $0 !~ /^promotion_gates:/ {
      in_pg=0
      section=""
      next
    }
    !in_pg { next }
    /^[[:space:]]{2}regex_only:[[:space:]]*$/ {
      section="regex"
      seen_regex=1
      next
    }
    /^[[:space:]]{2}high_or_critical:[[:space:]]*$/ {
      section="high"
      seen_high=1
      next
    }
    /^[[:space:]]{2}unknown_defaults:[[:space:]]*$/ {
      section="unknown"
      seen_unknown=1
      next
    }
    section == "regex" && /^[[:space:]]{4}max_effective_risk:[[:space:]]*medium([[:space:]#]|$)/ { regex_max=1 }
    section == "regex" && /^[[:space:]]{4}evidence_field:[[:space:]]*fallback_result([[:space:]#]|$)/ { regex_evidence=1 }
    section == "regex" && /^[[:space:]]{4}forbidden_field:[[:space:]]*validator_result([[:space:]#]|$)/ { regex_forbidden=1 }
    section == "high" && /^[[:space:]]{6}-[[:space:]]*/ {
      value=$0
      sub(/^[[:space:]]{6}-[[:space:]]*/, "", value)
      sub(/[[:space:]#].*$/, "", value)
      mark_list(value)
    }
    section == "unknown" && /^[[:space:]]{4}unlisted_rule:[[:space:]]*unknown([[:space:]#]|$)/ { unknown_rule=1 }
    section == "unknown" && /^[[:space:]]{4}unlisted_boundary:[[:space:]]*unknown([[:space:]#]|$)/ { unknown_boundary=1 }
    section == "unknown" && /^[[:space:]]{4}unmapped_stack:[[:space:]]*unknown([[:space:]#]|$)/ { unknown_stack=1 }
    section == "unknown" && /^[[:space:]]{4}unmapped_evidence_type:[[:space:]]*unknown([[:space:]#]|$)/ { unknown_evidence=1 }
    END {
      if (!seen_pg) print "shadow rule registry missing promotion_gates"
      if (!seen_regex) print "shadow rule registry missing regex_only gate"
      if (!regex_max) print "shadow rule registry regex_only.max_effective_risk must be medium"
      if (!regex_evidence) print "shadow rule registry regex_only.evidence_field must be fallback_result"
      if (!regex_forbidden) print "shadow rule registry regex_only.forbidden_field must be validator_result"
      if (!seen_high) print "shadow rule registry missing high_or_critical gate"
      if (!parser) print "shadow rule registry high_or_critical missing parser_backed_validator"
      if (!test) print "shadow rule registry high_or_critical missing test_assertion"
      if (!runtime) print "shadow rule registry high_or_critical missing runtime_trace"
      if (!waiver) print "shadow rule registry high_or_critical missing valid_waiver"
      if (!seen_unknown) print "shadow rule registry missing unknown_defaults"
      if (!unknown_rule) print "shadow rule registry must default unlisted_rule to unknown"
      if (!unknown_boundary) print "shadow rule registry must default unlisted_boundary to unknown"
      if (!unknown_stack) print "shadow rule registry must default unmapped_stack to unknown"
      if (!unknown_evidence) print "shadow rule registry must default unmapped_evidence_type to unknown"
    }
  ' "$rule_file")"

  if [[ -n "$failures" ]]; then
    while IFS= read -r failure_line; do
      [[ -n "$failure_line" ]] || continue
      fail "${failure_line} (${rule_file})"
    done < <(printf '%s\n' "$failures")
  else
    pass "shadow rule registry promotion gates are scoped and complete"
  fi
}

check_rule_registry_mapping_contracts() {
  local rule_file="$1"
  local catalog_file="$2"
  local regex_file="$3"
  local catalog_map
  local regex_map
  local failures

  catalog_map="$(mktemp "${TMPDIR:-/tmp}/validate_docs_catalog_map.XXXXXX")"
  regex_map="$(mktemp "${TMPDIR:-/tmp}/validate_docs_regex_map.XXXXXX")"
  collect_validator_evidence_map "$catalog_file" > "$catalog_map"
  collect_regex_evidence_map "$regex_file" > "$regex_map"

  failures="$(awk -v catalog_file="$catalog_map" -v regex_file="$regex_map" '
    FILENAME == catalog_file {
      catalog[$1]=$2
      next
    }
    FILENAME == regex_file {
      regex[$1]=$2
      next
    }
    function flush_fallback() {
      if (pending_fallback && !fallback_cap_seen) {
        print "fallback mapping missing fallback_max_risk for " pending_fallback_id " under " current_evidence " at line " pending_fallback_line
      }
      pending_fallback=0
      fallback_cap_seen=0
      pending_fallback_id=""
      pending_fallback_line=0
    }
    /^[[:space:]]{8}[a-z_][a-z0-9_]*:[[:space:]]*$/ {
      flush_fallback()
      current_evidence=$0
      sub(/^[[:space:]]+/, "", current_evidence)
      sub(/:.*$/, "", current_evidence)
      next
    }
    current_evidence != "" && /^[[:space:]]{10}primary:[[:space:]]*/ {
      id=$0
      sub(/^[[:space:]]+primary:[[:space:]]*/, "", id)
      sub(/[[:space:]#].*$/, "", id)
      if ((id in catalog) && catalog[id] != current_evidence) {
        print "primary validator evidence_type mismatch for " id ": expected " current_evidence ", found " catalog[id] " at line " NR
      }
      next
    }
    current_evidence != "" && /^[[:space:]]{10}fallback:[[:space:]]*/ {
      flush_fallback()
      id=$0
      sub(/^[[:space:]]+fallback:[[:space:]]*/, "", id)
      sub(/[[:space:]#].*$/, "", id)
      pending_fallback=1
      pending_fallback_id=id
      pending_fallback_line=NR
      if ((id in regex) && regex[id] != current_evidence) {
        print "fallback regex evidence_type mismatch for " id ": expected " current_evidence ", found " regex[id] " at line " NR
      }
      next
    }
    current_evidence != "" && /^[[:space:]]{10}fallback_max_risk:[[:space:]]*/ {
      value=$0
      sub(/^[[:space:]]+fallback_max_risk:[[:space:]]*/, "", value)
      sub(/[[:space:]#].*$/, "", value)
      if (value !~ /^(low|medium)$/) {
        print "fallback_max_risk must be low|medium in shadow rule registry: " value " at line " NR
      }
      if (pending_fallback) {
        fallback_cap_seen=1
      }
      next
    }
    END {
      flush_fallback()
    }
  ' "$catalog_map" "$regex_map" "$rule_file")"

  rm -f "$catalog_map" "$regex_map"

  if [[ -n "$failures" ]]; then
    while IFS= read -r failure_line; do
      [[ -n "$failure_line" ]] || continue
      fail "${failure_line} (${rule_file})"
    done < <(printf '%s\n' "$failures")
  else
    pass "shadow rule registry mapping contracts are structurally valid"
  fi
}

check_rule_registry_refs_exist() {
  local rule_file="$1"
  local ref_kind="$2"
  local known_ids="$3"
  local known_label="$4"
  local ref
  local missing_count=0

  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    if ! list_has_line "$known_ids" "$ref"; then
      fail "rule registry references unknown ${ref_kind} ${known_label}: ${ref} (${rule_file})"
      missing_count=$((missing_count + 1))
    fi
  done < <(collect_rule_registry_refs "$rule_file" "$ref_kind")

  if (( missing_count == 0 )); then
    pass "rule registry ${ref_kind} references resolve against ${known_label}"
  fi
}

check_rule_registry_has_mappings() {
  local rule_file="$1"
  local rule_count
  local primary_count
  local effect_type_count
  local effect_type_failures

  check_file_contains_pattern "$rule_file" "^[[:space:]]{0,2}rules:" "shadow rule registry declares rules block" "shadow rule registry missing rules block (${rule_file})"

  rule_count="$(grep -E '^[[:space:]]{2,}[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+:' "$rule_file" 2>/dev/null | grep -Ev '@v[0-9]+:' | wc -l | tr -d ' ' || true)"
  primary_count="$(collect_rule_registry_refs "$rule_file" "primary" | wc -l | tr -d ' ')"
  effect_type_count="$(grep -E '^[[:space:]]{4}allowed_effect_types:[[:space:]]*\[[a-z0-9_,[:space:]]+\]' "$rule_file" 2>/dev/null | wc -l | tr -d ' ' || true)"

  if (( rule_count == 0 )); then
    fail "shadow rule registry must contain at least one rule id mapping: $rule_file"
  else
    pass "shadow rule registry contains rule id mappings (${rule_count})"
  fi

  if (( primary_count == 0 )); then
    fail "shadow rule registry must contain at least one primary validator mapping: $rule_file"
  else
    pass "shadow rule registry contains primary validator mappings (${primary_count})"
  fi

  if (( effect_type_count < rule_count )); then
    fail "shadow rule registry must declare allowed_effect_types for every rule (${effect_type_count}/${rule_count}): $rule_file"
  else
    pass "shadow rule registry declares allowed_effect_types for every rule (${effect_type_count})"
  fi

  effect_type_failures="$(awk '
    /^[[:space:]]{4}allowed_effect_types:[[:space:]]*/ {
      value=$0
      sub(/^[[:space:]]+allowed_effect_types:[[:space:]]*\[/, "", value)
      sub(/\].*$/, "", value)
      n=split(value, parts, ",")
      for (i=1; i<=n; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
        if (parts[i] !~ /^[a-z][a-z0-9_]*$/) {
          print "invalid allowed_effect_types value: " parts[i] " at line " NR
        }
      }
    }
  ' "$rule_file")"
  if [[ -n "$effect_type_failures" ]]; then
    while IFS= read -r failure_line; do
      [[ -n "$failure_line" ]] || continue
      fail "${failure_line} (${rule_file})"
    done < <(printf '%s\n' "$effect_type_failures")
  else
    pass "shadow rule registry allowed_effect_types values are structurally valid"
  fi
}

check_shadow_policy_files() {
  local catalog_file="$POLICY_DIR/shadow-validator-catalog.md"
  local regex_file="$POLICY_DIR/shadow-regex-patterns.md"
  local rule_file="$POLICY_DIR/shadow-rule-registry.md"
  local required_prefix
  local catalog_ids
  local regex_ids

  check_file_exists "$catalog_file" "shadow validator catalog"
  check_file_exists "$regex_file" "shadow regex pattern registry"
  check_file_exists "$rule_file" "shadow rule registry"

  [[ -f "$catalog_file" && -f "$regex_file" && -f "$rule_file" ]] || return

  check_line_limit "$catalog_file" "$MAX_POLICY_LINES" "shadow validator catalog"
  check_line_limit "$regex_file" "$MAX_POLICY_LINES" "shadow regex pattern registry"
  check_line_limit "$rule_file" "$MAX_POLICY_LINES" "shadow rule registry"

  check_field_non_empty "$catalog_file" "catalog_id" "shadow validator catalog" || true
  check_field_non_empty "$catalog_file" "catalog_version" "shadow validator catalog" || true
  check_field_non_empty "$catalog_file" "status" "shadow validator catalog" || true
  check_any_field_non_empty "$catalog_file" "shadow validator catalog" "linked_task" "template_linked_task" || true
  check_any_field_non_empty "$catalog_file" "shadow validator catalog" "linked_decision" "template_linked_decision" || true
  check_field_non_empty "$catalog_file" "purpose" "shadow validator catalog" || true
  check_field_non_empty "$catalog_file" "last_updated" "shadow validator catalog" || true

  check_field_non_empty "$regex_file" "registry_id" "shadow regex pattern registry" || true
  check_field_non_empty "$regex_file" "registry_version" "shadow regex pattern registry" || true
  check_field_non_empty "$regex_file" "status" "shadow regex pattern registry" || true
  check_any_field_non_empty "$regex_file" "shadow regex pattern registry" "linked_task" "template_linked_task" || true
  check_any_field_non_empty "$regex_file" "shadow regex pattern registry" "linked_decision" "template_linked_decision" || true
  check_field_non_empty "$regex_file" "purpose" "shadow regex pattern registry" || true
  check_field_non_empty "$regex_file" "last_updated" "shadow regex pattern registry" || true

  check_field_non_empty "$rule_file" "registry_id" "shadow rule registry" || true
  check_field_non_empty "$rule_file" "registry_version" "shadow rule registry" || true
  check_field_non_empty "$rule_file" "status" "shadow rule registry" || true
  check_any_field_non_empty "$rule_file" "shadow rule registry" "linked_task" "template_linked_task" || true
  check_any_field_non_empty "$rule_file" "shadow rule registry" "linked_decisions" "template_linked_decisions" || true
  check_field_non_empty "$rule_file" "purpose" "shadow rule registry" || true
  check_field_non_empty "$rule_file" "last_updated" "shadow rule registry" || true

  for required_prefix in any java js ts py spring_boot express react fastapi jpa sql; do
    check_file_contains_pattern \
      "$catalog_file" \
      "^[[:space:]]{2,}${required_prefix}\\.[a-z0-9_.]+@v[0-9]+:" \
      "shadow validator catalog includes ${required_prefix} versioned validators" \
      "shadow validator catalog missing ${required_prefix} versioned validator prefix (${catalog_file})"
  done
  check_catalog_probe_coverage "$catalog_file"
  check_policy_loader_contract

  check_file_contains_pattern \
    "$regex_file" \
    "^[[:space:]]{2,}[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+@v[0-9]+:" \
    "shadow regex registry uses versioned regex ids" \
    "shadow regex registry has no versioned regex ids (${regex_file})"
  check_file_contains_pattern "$regex_file" "allowed_paths:" "shadow regex registry declares allowed_paths" "shadow regex registry missing allowed_paths (${regex_file})"
  check_file_contains_pattern "$regex_file" "excluded_paths:" "shadow regex registry declares excluded_paths" "shadow regex registry missing excluded_paths (${regex_file})"
  check_file_contains_pattern "$regex_file" "validates:" "shadow regex registry declares validates" "shadow regex registry missing validates (${regex_file})"
  check_file_contains_pattern "$regex_file" "cannot_validate:" "shadow regex registry declares cannot_validate" "shadow regex registry missing cannot_validate (${regex_file})"
  check_file_contains_pattern "$regex_file" "max_promotion_risk:" "shadow regex registry declares max_promotion_risk" "shadow regex registry missing max_promotion_risk (${regex_file})"

  check_policy_risk_field_values "$regex_file" "max_promotion_risk" "shadow regex pattern registry"

  check_rule_registry_has_mappings "$rule_file"
  check_rule_registry_ref_versions "$rule_file"
  check_rule_registry_promotion_gates "$rule_file"
  check_rule_registry_mapping_contracts "$rule_file" "$catalog_file" "$regex_file"

  catalog_ids="$(collect_versioned_registry_ids_in_block "$catalog_file" "validators")"
  regex_ids="$(collect_versioned_registry_ids_in_block "$regex_file" "regex_patterns")"
  check_rule_registry_refs_exist "$rule_file" "primary" "$catalog_ids" "validator catalog id"
  check_rule_registry_refs_exist "$rule_file" "fallback" "$regex_ids" "regex pattern id"

  # The check_any_field_non_empty calls above prove a link field is PRESENT;
  # these resolve what it points at (advisory tier, adoption-gated).
  check_policy_decision_links "$catalog_file" "shadow validator catalog" "linked_decision" "linked_decisions"
  check_policy_decision_links "$regex_file" "shadow regex pattern registry" "linked_decision" "linked_decisions"
  check_policy_decision_links "$rule_file" "shadow rule registry" "linked_decision" "linked_decisions"
}
