#!/usr/bin/env bats

load codeguide_helper

AUDIT() {
  python3 "$SCRIPTS_DIR/shadow_reader_audit.py" "$@"
}

@test "shadow reader audit passes on the shipped skill with nothing unclassified" {
  run AUDIT
  [ "$status" -eq 0 ]
  assert_contains "$output" "unclassified: 0"
  # Positive anchors: the audit must actually be finding readers and telling the
  # three classes apart, not reporting zero because it found nothing at all.
  assert_contains "$output" "scripts/shadow_rationale_report.py: direct"
  assert_contains "$output" "scripts/shadow_coverage_report.py: transitive"
  assert_contains "$output" "scripts/shadow_policy_loader.py: excluded"
  # The two readers the task rewired are now compliant, not
  # excused. Pinning them as `direct` means DROPPING the delegation fails here instead of
  # quietly reappearing as an exclusion. It does not catch a partial revert: the audit
  # classifies by naming shadow_doc_parse, so a revert that leaves the import or the
  # heredoc in place still reads as `direct` -- that case is caught by the mutation-proven
  # behavior tests in validate_docs.bats and shadow_core.bats, not here.
  assert_contains "$output" "scripts/validate_docs.d/10-parse.sh: direct"
  assert_contains "$output" "scripts/shadow_effect_writer.py: direct"
  # The two WRITERS of the same capsules. doc_garden.sh sat in EXCLUSIONS on "not on shadow
  # fields", the reason the task rejected for the reader, while it
  # rewrote a fenced example as if it were the real field; run_external_plan_reviews.sh sat
  # there on a polarity conflict that was a reason to SPLIT its one helper, not to leave the
  # ORCH.md writer fence-blind. Both now reach the shared
  # reader through the ONE sourced shell adapter, so both are `transitive` -- and asserting
  # that is what makes the audit understand a `source` edge instead of losing a reader every
  # time a duplicated helper is de-duplicated into a shared file.
  assert_contains "$output" "scripts/doc_garden.sh: transitive"
  assert_contains "$output" "scripts/run_external_plan_reviews.sh: transitive"
  assert_contains "$output" "scripts/codeguide_doc_lines.sh: direct"
  # The extraction moved the naming heredocs into real .py files, so validate_docs.sh now
  # reaches the reader through its `if ! source` guard on codeguide_doc_lines.sh, and
  # 20-rules-shadow.sh is excluded because its field reads route through 10-parse.sh and
  # classified .py helpers (see EXCLUSIONS).
  assert_contains "$output" "scripts/validate_docs.sh: transitive"
  assert_contains "$output" "scripts/validate_docs.d/20-rules-shadow.sh: excluded"
  # The shared module itself, which became a candidate when it grew read_lines(). A module
  # cannot import itself, so this classification is by identity, not by naming.
  assert_contains "$output" "scripts/shadow_doc_parse.py: direct"
  # Discovery must not depend on a comment: deleting the duplicated fence state machine
  # from this file removed its last ``` literal -- which lived in the deleted docstring --
  # and dropped a live delegating reader out of the candidate set until the candidate rule
  # was widened to "names the shared reader".
  assert_contains "$output" "scripts/shadow_source_digest.py: direct"
}

@test "shadow reader audit reports an exclusion that is already compliant" {
  # A live reader kept in EXCLUSIONS is a silent safety net: drop the delegation later
  # and the file falls back to `excluded` on an unread reason instead of surfacing as
  # UNCLASSIFIED. The shipped tree must carry none, and the report must be able to
  # name one -- both halves, or this proves nothing.
  run AUDIT
  [ "$status" -eq 0 ]
  refute_contains "$output" "already reaches shadow_doc_parse"

  run python3 -c "
import sys
sys.path.insert(0, '$SCRIPTS_DIR')
import shadow_reader_audit as A
A.EXCLUSIONS['scripts/validate_docs.d/10-parse.sh'] = 'fixture: stale entry for a now-compliant reader'
sys.exit(A.main(['--skill-root', '$SCRIPTS_DIR/..']))
"
  [ "$status" -eq 0 ]
  assert_contains "$output" "scripts/validate_docs.d/10-parse.sh: excluded but already reaches shadow_doc_parse (direct); drop the exclusion"
}

@test "shadow reader audit records every exclusion with a reason" {
  # An exclusion with an empty reason is an unrecorded reader wearing a pass.
  run python3 -c "
import sys
sys.path.insert(0, '$SCRIPTS_DIR')
import shadow_reader_audit as A
bad = [k for k, v in A.EXCLUSIONS.items() if not v or not v.strip()]
print('empty_reasons: %d' % len(bad))
"
  [ "$status" -eq 0 ]
  assert_contains "$output" "empty_reasons: 0"
}

@test "shadow reader audit fails closed when a new unclassified reader appears" {
  # The whole point: the next reader anyone adds is a finding until classified.
  # -01 and -02 both swept by hand and both missed one; this is that sweep as an assertion.
  local fake="$SCRIPTS_DIR/shadow_zz_audit_fixture.py"
  cat > "$fake" <<'EOF'
from pathlib import Path


def read_role(shadow_dir):
    for doc in Path(shadow_dir).rglob("*.md"):
        for line in doc.read_text(encoding="utf-8").splitlines():
            if line.startswith("- doc_role:"):
                return line.split(":", 1)[1].strip()
    return ""
EOF
  run AUDIT
  rm -f "$fake"
  [ "$status" -eq 1 ]
  assert_contains "$output" "scripts/shadow_zz_audit_fixture.py: UNCLASSIFIED"
  assert_contains "$output" "unclassified: 1"
}

@test "shadow reader audit reports an exclusion that is no longer a reader" {
  # Stale bookkeeping would silently absolve a future reader reclaiming that path.
  run python3 -c "
import sys
sys.path.insert(0, '$SCRIPTS_DIR')
import shadow_reader_audit as A
A.EXCLUSIONS['scripts/not_a_real_reader.py'] = 'fixture'
sys.exit(A.main(['--skill-root', '$SCRIPTS_DIR/..']))
"
  [ "$status" -eq 0 ]
  assert_contains "$output" "scripts/not_a_real_reader.py: excluded but no longer detected"
}

@test "shadow reader audit classifies transitive delegation, not just direct imports" {
  # shadow_coverage_report.py reaches the shared reader through shadow_source_digest.
  # A sweep keyed to a direct import would call it non-compliant and erode trust.
  run python3 -c "
import sys
sys.path.insert(0, '$SCRIPTS_DIR')
import shadow_reader_audit as A
rows = dict(A.classify(__import__('pathlib').Path('$SCRIPTS_DIR/..') / 'scripts'))
print('coverage: %s' % rows['scripts/shadow_coverage_report.py'])
print('impact: %s' % rows['scripts/shadow_impact_report.py'])
"
  [ "$status" -eq 0 ]
  assert_contains "$output" "coverage: transitive"
  assert_contains "$output" "impact: transitive"
}

@test "shadow reader audit does not certify a shell reader on a COMMENT mention" {
  # DISCOVERY may use a comment -- naming the shared reader anywhere puts a file in the set
  # that must be classified, and widening a candidate set only adds work. CLASSIFICATION is
  # the opposite: `direct` means the file would still reach the reader if every `source`
  # edge were cut, and a sentence of prose does not. The two were the same substring test,
  # so adding a comment to `run_external_plan_reviews.sh` about what happens "with
  # shadow_doc_parse.py absent" silently promoted it from `transitive` to `direct` on the
  # strength of the explanation. Asserted on a FIXTURE
  # rather than on that comment, so rewording it cannot quietly unbind this.
  local fake_skill="$TEST_WORKSPACE/comment-skill"
  cp -R "$SCRIPTS_DIR/.." "$fake_skill"
  local reader="$fake_skill/scripts/comment_only_reader.sh"
  # Reads a shadow document (so it is a candidate), names the shared reader ONLY in a
  # comment, and reaches it through nothing.
  cat > "$reader" <<'SH'
# A reader that mentions shadow_doc_parse only in prose, never in code.
# doc_role: read from docs/shadow via grep, no shared reader involved.
comment_only_field() {
  grep -E "^- doc_role:" "$1" | head -n 1
}
SH

  run python3 -c "
import sys
sys.path.insert(0, '$SCRIPTS_DIR')
import shadow_reader_audit as A
sys.exit(A.main(['--skill-root', '$fake_skill']))
"
  # It must NOT come back certified. UNCLASSIFIED is the loud answer and the right one:
  # the file really does read a shadow document and really does not reach the shared reader.
  refute_contains "$output" "scripts/comment_only_reader.sh: direct"
  assert_contains "$output" "scripts/comment_only_reader.sh: UNCLASSIFIED"
  [ "$status" -ne 0 ]

  # Positive half: the same file naming the reader in CODE is certified, so this is about
  # comments and not about the file being a fixture.
  cat > "$reader" <<'SH'
comment_only_field() {
  python3 -c "import shadow_doc_parse" && grep -E "^- doc_role:" "$1" | head -n 1
}
SH
  run python3 -c "
import sys
sys.path.insert(0, '$SCRIPTS_DIR')
import shadow_reader_audit as A
sys.exit(A.main(['--skill-root', '$fake_skill']))
"
  assert_contains "$output" "scripts/comment_only_reader.sh: direct"
}
