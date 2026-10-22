#!/usr/bin/env python3
"""Enforce the shadow-document reader inventory: every reader is classified, or this fails.

The task and -02 both shipped a "closing sweep" performed by hand,
and both swept by SPELLING -- -01 grepped `startswith(fence)`/`infence` and missed an
`in_fence` local; -02 grepped for fence literals and missed a reader whose defect is
that it owns no fence literal at all. A narrative sweep proves nothing about the next
reader anyone adds. This is the same sweep as an assertion.

Discovery is SEMANTIC, not spelling-keyed: a candidate is any file under scripts/ that
both names the shadow tree and reads document text. It cannot be evaded by renaming a
variable, and a reader with no fence code is still a candidate -- which is precisely the
case the -02 sweep could not see.

Classification, in order:
  direct      -- names shadow_doc_parse
  transitive  -- its dependency closure reaches a direct consumer: python `import` for
                 .py files, shell `source` for .sh files. A `source` is textual inclusion,
                 so the sourced functions ARE the sourcing script's functions -- stronger
                 evidence than an import, not weaker, and it is executable code rather than
                 a comment, which is the criterion this audit refuses to trust.
  excluded    -- listed in EXCLUSIONS below WITH a reason
  unclassified-> failure. A new reader is a finding until someone decides which it is.

Exit codes: 0 all classified, 1 at least one unclassified, 2 usage/IO error.
"""
from __future__ import annotations

import argparse
import ast
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True

SHARED = "shadow_doc_parse"

# Names the shadow tree.
SHADOW_REF = re.compile(r"docs/shadow|SHADOW_DIR|shadow_dir|shadow_root")
# ...or implements the shadow document grammar without naming the tree. A generic
# helper handed a shadow path by its caller is a reader by USE: extract_field_value
# in validate_docs.d/10-parse.sh names no shadow path, and was the worst reader we
# had until the task delegated it to the shared reader.
#
# `\^-\\` is the bash `[[ =~ ]]` spelling of the same column-0 bullet anchor, where the
# space after the dash has to be backslash-escaped: `^-\ (TASK-...)`. It was missing, so
# the file holding the task-index row walk was a candidate only for as long as some
# unrelated fence literal happened to sit in it, and dropped out the moment one was
# removed. A discovery rule whose
# coverage depends on a comment is the spelling-keyed sweep this audit replaced.
DOC_GRAMMAR = re.compile(r"""\^\s*-\s|\^- |\^-\\|- \$\{?key|chr\(96\)|```|~~~""")
# Reads document text. Shell readers count via the tools they use on a path.
DOC_READ = re.compile(
    r"read_text|readlines|\.open\(|open\(|rglob|iterdir|"
    r"\bgrep\b|\bawk\b|\bsed\b|\bcat\b|while\s+IFS=.*read"
)

# Every entry is a decision someone made, with the reason that justifies it. An
# exclusion without a reason is not an exclusion, it is an unrecorded reader.
EXCLUSIONS = {
    "scripts/shadow_policy_loader.py": (
        "Extracts fenced block BODIES as the policy-registry payload and errors on an "
        "unclosed block. It needs the info string and the block contents, which the "
        "shared reader deliberately discards. Out of boundary by the recorded decision."
    ),
    "scripts/check_english_docs.sh": (
        "Language-policy scan over the whole skill root, not the shadow tree specifically. "
        "It must also strip INLINE code spans, which the shared reader does not model. "
        "Cannot produce the driver failure mode: it reads no shadow field."
    ),
    "scripts/init_docs_scaffold.sh": (
        "Writes template documents; the fence markers in it are emitted content, not a reader."
    ),
    # scripts/doc_garden.sh was excluded here on the reason "Operates on task/plan/
    # orchestration capsules ... not on shadow fields" -- verbatim the reason
    # The task rejected for extract_field_value when it corrected
    # the blast radius. It was never true of what the file DOES: it answers the `- key:`
    # question in order to EDIT the answer, fence-blind, with an unaddressed `sed` that
    # rewrote a quoted template example as if it were the real field (r03 finding 2). It
    # now resolves the line through shadow_doc_parse.numbered_content_lines -- via the one
    # sourced adapter codeguide_doc_lines.sh, so it classifies as `transitive` rather than
    # `direct` -- and the entry is gone rather than reworded.
    #
    # scripts/validate_docs.d/10-parse.sh, scripts/validate_docs.sh and
    # scripts/shadow_effect_writer.py were listed here as KNOWN LIVE DIVERGENCES tracked by
    # The task. That task rewired extract_field_value and
    # leading_metadata_value onto the shared reader, so all three now classify as `direct`
    # and an exclusion for them would be dead text -- see the "Shadowed exclusions" report.
    #
    # The rest read structured payloads or non-shadow capsules. None resolves a shadow
    # field out of shadow markdown, so none can produce the driver failure mode -- one
    # document, two rules, opposite verdicts.
    "scripts/shadow_apply_gate.py": "Reads JSON payloads, not shadow markdown fields.",
    "scripts/shadow_llm_candidate_wrapper.py": "Reads JSON/text payloads, not shadow markdown fields.",
    "scripts/shadow_user_decision_wrapper.py": "Reads JSON payloads, not shadow markdown fields.",
    "scripts/shadow_v2_review_packet_generator.py": "Reads JSON payloads, not shadow markdown fields.",
    "scripts/shadow_v2_user_decision_assistant.py": "Reads JSON payloads, not shadow markdown fields.",
    "scripts/shadow_v2_gate_skeleton.py": (
        "Reads external-review request/provenance handoff files under docs/orchestration, "
        "not shadow documents."
    ),
    "scripts/validate_docs_review_evidence.py": (
        "Verifies wrapper-generated external-review artifacts under docs/orchestration "
        "(request, response, provenance), not shadow documents; same class as "
        "shadow_v2_gate_skeleton.py. It deliberately keeps the wrapper's own `^- key:` "
        "first-match grammar (run_external_plan_reviews.sh response_field_value) instead of "
        "the fence-aware shared reader: these are machine-written bullet lists with no fenced "
        "examples, and the evidence check has to read them exactly the way the wrapper that "
        "produced them did. The `- key:` regex is what the audit's criterion matches, not a "
        "shadow-field read."
    ),
    "scripts/run_codeguide.sh": "Front CLI dispatcher; reads no document fields itself.",
    # scripts/run_external_plan_reviews.sh was excluded here on a polarity conflict: ONE
    # fence-blind `extract_field_value` served both the PLAN/TASK/DECISION capsules and the
    # EXTERNAL MODEL RESPONSES, and a fence-aware read would turn a model that wraps its
    # answer in a ``` block from parsed into empty. The conflict was real and the conclusion
    # was too wide -- it was a reason to SPLIT the helper, not to leave the capsule half and
    # the ORCH.md WRITER fence-blind. The capsule reads
    # are now `capsule_field_value` (shared reader) and the write is line-addressed through
    # the same adapter doc_garden.sh uses, so the file classifies as `transitive`. What
    # remains deliberately fence-BLIND is `response_field_value`, named as such in the code
    # and recorded beside `check_file_contains_pattern` in the PLAN residual list -- the two
    # places in this tree where fence-blindness is load-bearing. Neither is an exclusion:
    # an exclusion says "this file does not answer the shared question", and both files do.
    # Rewriting this file's private `^- key:` probes as field_key_present calls briefly
    # dropped it out of the candidate set entirely -- no shadow path named, no DOC_GRAMMAR
    # match left -- and the audit then printed it as a STALE exclusion where HEAD printed
    # nothing. Coverage that shrinks as a side effect of a fix is a finding, not a cleanup
    # The reason below is rewritten to
    # say what the file is TODAY rather than left as inherited text.
    "scripts/validate_docs.d/30-rules-task.sh": (
        "Task/plan capsule rules; reads no shadow field. Its `- key:` field reads and "
        "presence probes go through 10-parse.sh (extract_field_value / field_key_present), "
        "which delegate the fence rule to the shared reader. What it still owns is the "
        "task-index ROW grammar, `^- (TASK-...)`, which is not the `- key:` field grammar "
        "and is not a shadow document -- it walks the fence-stripped copy so it agrees "
        "with task_index_row_present, and the binding for that is behavioral, in "
        "'validate_docs reads a task-index row quoted inside a fence as no row at all'. "
        "The issue-README row probes it used to own inline -- escaped at the call site and "
        "greping the RAW file -- moved to issue_index_row_present in 10-parse.sh, beside "
        "the two sibling row helpers and with their contract "
        "(the task r01 finding 4)."
    ),
    "scripts/validate_docs.d/40-rules-orchestration.sh": (
        "Orchestration capsule rules over task/plan/orchestration docs, not shadow documents. "
        "Its `- key:` reads go through 10-parse.sh. It keeps ONE private grammar, the awk in "
        "check_tmp_path_references, because that rule must scan the whole file list in a "
        "single pass (the tracked issue) and the fence-stripped cache "
        "is keyed per file. It no longer DIVERGES: the task replaced "
        "its toggle-on-any-marker state machine with the same CommonMark opener-character/"
        "length rule the shared reader uses, asserted equal to it by test rather than by "
        "naming it. Naming it would flip this file to `direct` on a COMMENT, which is the "
        "audit criterion's known weakness, not evidence of agreement."
    ),
    "scripts/validate_docs.d/20-rules-shadow.sh": (
        "Shadow graph/schema/digest rules. Its `- key:` field reads go through 10-parse.sh "
        "(extract_field_value / field_key_present / extract_shadow_field), which delegate the "
        "fence rule to the shared reader, and through classified .py helpers it invokes as "
        "subprocesses. The two raw greps it still owns (source_of_truth_digest prefilter at "
        "check_shadow_source_digest, source_of_truth_paths prefilter at "
        "check_shadow_source_paths_exist) are spawn-guard prefilters, not the reader: the "
        "verdict is decided by shadow_source_digest.py (classified `direct`), the same "
        "prefilter arrangement the task accepted for r02 finding 9. "
        "It keeps one private grammar, the awk in bucket_index_has_units over the "
        "fence-stripped cache, justified identically to 40-rules-orchestration.sh."
    ),
}


def candidates(scripts_dir: Path) -> list[Path]:
    found = []
    for path in sorted(scripts_dir.rglob("*")):
        if not path.is_file() or path.suffix not in (".py", ".sh"):
            continue
        if path.name == Path(__file__).name:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            raise SystemExit(f"error: cannot read {path}: {exc}")
        # A file that NAMES the shared reader is in the boundary by construction, and
        # discovering it that way cannot depend on a comment. Without this, deleting a
        # duplicated fence state machine from shadow_source_digest.py removed the file's
        # last ``` literal -- which sat in the docstring of the code being deleted -- and
        # dropped a live delegating reader out of the candidate set entirely, the same
        # coverage-shrinks-as-a-side-effect-of-a-fix failure r02 caught on
        # 30-rules-task.sh. Widening DISCOVERY is safe
        # in a way that widening the CLASSIFICATION criterion is not: it can only add
        # files to the set that must be classified.
        names_shared = SHARED in text
        if (names_shared or SHADOW_REF.search(text) or DOC_GRAMMAR.search(text)) and DOC_READ.search(text):
            found.append(path)
    return found


# `source "$THIS_DIR/x.sh"` / `. "${SCRIPT_DIR}/dir/x.sh"`. Only a literal filename counts:
# a sourced path built from a loop variable is not a dependency this audit can prove, and
# guessing one would be the same false certification as reading a comment. A conditional
# `if ! source ...` guard is still a real source edge -- the file executes the source when
# the condition holds -- so an `if`/`if !` prefix is accepted.
_SHELL_SOURCE_RE = re.compile(
    r"^[ \t]*(?:if[ \t]+(?:![ \t]+)?)?(?:source|\.)[ \t]+\"?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/([A-Za-z0-9_./-]+\.sh)\"?",
    re.M,
)


def local_imports(path: Path, known: set[str]) -> set[str]:
    """Sibling modules this file depends on, by the mechanism its language actually uses.

    Python: `import`/`from ... import`, keyed by module stem.
    Shell: `source`/`.` of a sibling script, keyed by file NAME (`x.sh`), so a .py stem and
    a .sh name can never collide in the one dependency graph below.

    The shell half exists because the `- key:` line lookup that both writers use now lives
    in ONE sourced adapter (codeguide_doc_lines.sh) instead of a private copy per tool. If
    the audit only understood python imports, moving the duplicate into a shared file would
    have dropped doc_garden.sh from `direct` to UNCLASSIFIED -- coverage shrinking as a side
    effect of a de-duplication, which is the exact failure mode r02 caught on 30-rules-task.sh
    and r03 caught on shadow_source_digest.py (the task).
    """
    if path.suffix == ".sh":
        return {Path(m).name for m in _SHELL_SOURCE_RE.findall(
            path.read_text(encoding="utf-8", errors="replace")
        )} & known
    if path.suffix != ".py":
        return set()
    try:
        tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"))
    except (OSError, SyntaxError):
        return set()
    names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
            names.add(node.module.split(".")[0])
    return names & known


def module_key(path: Path) -> str:
    return path.stem if path.suffix == ".py" else path.name


def classification_text(path: Path, text: str) -> str:
    """The text CLASSIFICATION may look at: comment-only mentions do not certify.

    DISCOVERY may use a comment -- naming the shared reader anywhere puts a file in the set
    that must be classified, and widening a candidate set can only add work. CLASSIFICATION
    is the opposite: calling a file `direct` on the strength of a comment is a FALSE
    certification, because `direct` means the file would still reach the reader if every
    `source` edge were cut, and a sentence of prose does not.

    That is not hypothetical. A comment added to `run_external_plan_reviews.sh` explaining
    what happens "with shadow_doc_parse.py absent" flipped it from `transitive` to `direct`
    on the strength of the explanation alone -- caught only because the round that de-duped
    the adapter had PINNED it as `transitive` (the task). Documenting
    a dependency is not having one, and the audit already records that this criterion cannot
    tell the two apart; this narrows it where the distinction is unambiguous.

    Shell only, deliberately. A `#` at the start of a stripped line is a comment in shell
    with no exceptions worth modelling here, whereas in python the same test would have to
    tell a docstring from `SHARED = "shadow_doc_parse"` -- a string LITERAL that is code --
    and getting that wrong would silently SHRINK coverage, which is the failure this audit
    exists to catch. Measured before narrowing: of the five shell files naming the reader,
    four name it in code and exactly one, `run_external_plan_reviews.sh`, names it only in a
    comment. The residual (a `#` line inside a shell heredoc carrying python) is an
    over-strip, and over-stripping can only move a file toward UNCLASSIFIED, which fails
    loudly rather than certifying quietly.
    """
    if path.suffix != ".sh":
        return text
    return "\n".join(
        line for line in text.split("\n") if not line.lstrip().startswith("#")
    )


def classify(scripts_dir: Path):
    modules = {module_key(p): p for p in scripts_dir.glob("*.py")}
    modules.update({module_key(p): p for p in scripts_dir.rglob("*.sh")})
    known = set(modules)
    direct = {
        name
        for name, path in modules.items()
        if SHARED in classification_text(
            path, path.read_text(encoding="utf-8", errors="replace")
        )
    }

    def reaches_shared(name: str, seen: set[str]) -> bool:
        if name in direct:
            return True
        if name in seen or name not in modules:
            return False
        seen.add(name)
        return any(reaches_shared(dep, seen) for dep in local_imports(modules[name], known))

    rows = []
    for path in candidates(scripts_dir):
        rel = f"scripts/{path.relative_to(scripts_dir)}"
        text = path.read_text(encoding="utf-8", errors="replace")
        if rel == f"scripts/{SHARED}.py":
            # The shared reader itself. It became a CANDIDATE the moment it grew a
            # `read_lines(path)` helper, and the naming
            # criterion cannot classify it: a module does not import itself, so the only
            # way for it to "name the shared reader" is a comment -- the exact false
            # certification the capsule already records this criterion cannot tell apart.
            # It is the definition, so it is compliant by construction.
            verdict = "direct"
        elif SHARED in classification_text(path, text):
            verdict = "direct"
        elif reaches_shared(module_key(path), set()):
            verdict = "transitive"
        elif rel in EXCLUSIONS:
            verdict = "excluded"
        else:
            verdict = "UNCLASSIFIED"
        rows.append((rel, verdict))
    return rows


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Audit shadow-document reader compliance.")
    parser.add_argument("--skill-root", default=str(Path(__file__).resolve().parent.parent))
    args = parser.parse_args(argv)

    scripts_dir = Path(args.skill_root) / "scripts"
    if not scripts_dir.is_dir():
        print(f"error: no scripts dir at {scripts_dir}", file=sys.stderr)
        return 2

    rows = classify(scripts_dir)
    unclassified = [rel for rel, verdict in rows if verdict == "UNCLASSIFIED"]

    print("# Shadow Reader Audit")
    print(f"- readers: {len(rows)}")
    print(f"- unclassified: {len(unclassified)}")
    print("## Readers")
    for rel, verdict in rows:
        print(f"- {rel}: {verdict}")
    print("## Unclassified")
    for rel in unclassified:
        print(f"- {rel}: reads shadow documents but neither consumes {SHARED} nor is excluded")

    # An exclusion for a file that is no longer a reader is stale bookkeeping: it would
    # silently absolve a future reader that reclaims the same path.
    listed = {rel for rel, _ in rows}
    print("## Stale exclusions")
    for rel in sorted(set(EXCLUSIONS) - listed):
        print(f"- {rel}: excluded but no longer detected as a shadow-document reader")

    # An exclusion for a file that now reaches the shared reader is not merely dead text:
    # it is a silent safety net. Remove the delegation later and the file falls back to
    # "excluded" on the strength of a reason nobody re-read, instead of surfacing as
    # UNCLASSIFIED. The task produced three of these by making
    # their files compliant; this report is what stopped them from going unnoticed.
    print("## Shadowed exclusions")
    for rel, verdict in rows:
        if rel in EXCLUSIONS and verdict in ("direct", "transitive"):
            print(f"- {rel}: excluded but already reaches {SHARED} ({verdict}); drop the exclusion")

    return 1 if unclassified else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
