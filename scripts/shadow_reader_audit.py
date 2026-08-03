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
  transitive  -- its python import closure reaches a direct consumer
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
# in validate_docs.d/10-parse.sh names no shadow path and is the worst reader we have.
DOC_GRAMMAR = re.compile(r"""\^\s*-\s|\^- |- \$\{?key|chr\(96\)|```|~~~""")
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
    "scripts/doc_garden.sh": (
        "Operates on task/plan/orchestration capsules and resume checkpoints, not on shadow "
        "fields. Its markdown reads never resolve a shadow reference."
    ),
    "scripts/validate_docs.d/10-parse.sh": (
        "KNOWN LIVE DIVERGENCE, NOT a clean exclusion. extract_field_value is a fence-blind "
        "`grep -E \"^- key:\" | head -1` used on shadow documents, so a fenced example can "
        "win over the real field: a bucket _index.md quoting the unit-overview template "
        "reports doc_role=unit_overview where the shared reader returns bucket_index. "
        "Rewiring its call sites changes strict-mode findings and needs its own before/after "
        "evidence. Tracked by the task."
    ),
    "scripts/validate_docs.sh": (
        "Call site of the reader above, not a reader itself: it holds no field grammar and "
        "reads shadow fields only through extract_field_value. Moves with "
        "the task."
    ),
    "scripts/shadow_effect_writer.py": (
        "KNOWN NARROWER DIVERGENCE, NOT a clean exclusion. leading_metadata_value reads "
        "`- doc_role:` from a shadow effect_map with no fence awareness, so a fenced example "
        "inside the leading metadata block can answer for the real field. Bounded to the "
        "first 80 lines and to text before the first `## ` heading, which makes it much "
        "harder to trip than extract_field_value but not impossible. The effect-map grammar "
        "is out of boundary by the recorded decision; this `doc_role` guard is not "
        "effect-map-specific. Tracked by the task."
    ),
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
    "scripts/run_codeguide.sh": "Front CLI dispatcher; reads no document fields itself.",
    "scripts/run_external_plan_reviews.sh": (
        "Writes and parses external-review handoff files under docs/orchestration; reads no shadow field."
    ),
    "scripts/validate_docs.d/30-rules-task.sh": "Task/plan capsule rules; reads no shadow field.",
    "scripts/validate_docs.d/40-rules-orchestration.sh": (
        "Orchestration capsule rules with their own awk grammar over task/plan/orchestration "
        "docs. Out of boundary by the recorded decision."
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
        if (SHADOW_REF.search(text) or DOC_GRAMMAR.search(text)) and DOC_READ.search(text):
            found.append(path)
    return found


def local_imports(path: Path, known: set[str]) -> set[str]:
    """Sibling modules this python file imports. Non-python files import nothing."""
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


def classify(scripts_dir: Path):
    modules = {p.stem: p for p in scripts_dir.glob("*.py")}
    known = set(modules)
    direct = {
        name
        for name, path in modules.items()
        if SHARED in path.read_text(encoding="utf-8", errors="replace")
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
        if SHARED in text:
            verdict = "direct"
        elif path.suffix == ".py" and reaches_shared(path.stem, set()):
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

    return 1 if unclassified else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
