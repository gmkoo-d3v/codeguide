#!/usr/bin/env python3
"""Read-only validator rule <-> test coverage matrix.

Inventories every column-0 `name() {` function defined in
scripts/validate_docs.d/*.sh and the scripts/validate_docs.sh adapter, finds
each function's fail()/soft_warn() emit sites, and classifies whether the
function's failure messages are exercised by anything under tests/*.bats.

Rule id == function name (same identity contract as the runtime FUNCNAME[1]
capture in 00-report.sh); a renamed function is a new, unlinked rule here too.

Classification is a static heuristic, not a coverage guarantee:
  - NO-EMIT: the function has no fail()/soft_warn() call sites (pure helper).
  - TESTED: at least one emit site has a DISTINCTIVE literal message prefix
    (defined below) and that exact substring appears in at least one
    tests/*.bats file.
  - UNTESTED: distinctive literal prefixes exist, but no tests/*.bats file
    contains any of them.
  - HEURISTIC-UNRESOLVED: emit sites exist but none has a distinctive
    literal prefix -- either every prefix is shorter than 12 characters
    (message built almost entirely from variables) or every long-enough
    prefix is ambiguous (below). This is a heuristic gap, not a
    "no test exists" claim.

A literal prefix (the text before the first `$` expansion) is DISTINCTIVE
only if it is >= 12 characters AND it is not a substring of any other rule's
long-enough literal prefix. The substring exclusion is the attribution
invariant: TESTED must mean "a test quotes THIS rule's message". A prefix
that also occurs inside another rule's message cannot be attributed to one
rule -- concretely, check_rule_registry_ref_versions' 14-char prefix
"rule registry " is equally the opening of check_rule_registry_refs_exist's
"rule registry references unknown ", and in practice it matched an unrelated
bats test TITLE containing those words, producing a false TESTED. Ambiguous
prefixes are excluded from matching entirely; a rule left with no
distinctive prefix is HEURISTIC-UNRESOLVED, never TESTED. A higher minimum
length was considered and rejected: the shortest genuine match in the
current corpus is 15 chars, so any cutoff excluding the 14-char false
positive sits on a knife edge, while the ambiguity rule removes the actual
failure mode (unattributable prefixes) instead of tuning around it.

Main-flow disclosure: fail()/soft_warn() sites at the TOP LEVEL of the
adapter (outside any function) carry rule id "main" at runtime -- they are
real, id-stable emit sites, and a function-only inventory would silently
hide ~30 of them. They are disclosed as one aggregate row (function "main",
module "adapter") with status MAIN-FLOW-AGGREGATE, the site count in the
MESSAGES column, and the bats files matched by any of their distinctive
literals under the same matching rules. The row is deliberately NOT
classified TESTED/UNTESTED: a single matched literal out of 30+
heterogeneous sites would mark the whole top-level flow "covered", which is
exactly the false confidence this tool exists to prevent. Main-flow literals
DO participate in the ambiguity universe, and the row never affects
--exit-code. Module files currently have zero top-level emit sites; if one
ever appears it is folded into this same disclosure row rather than dropped
(its runtime id would differ -- bash reports sourced-file top level as
"source" -- but silent invisibility is the worse failure).

The parser is heredoc-aware: several rule functions in scripts/validate_docs.d
shell out to python3 via `<<'PY' ... PY` heredocs whose bodies contain
column-0 `}` (dict/set literals) and column-0 `def ...():` lines. A scanner
that is not heredoc-aware slices function bodies at the first such `}` and
silently truncates or merges functions. This tool tracks heredoc delimiters
(`<<'PY'`, `<<EOF`, `<<-TAG`, ...) and treats everything between the opener
and its exact terminator line as opaque -- it is never scanned for a column-0
`}` (end of function) or a column-0 `name() {` (start of function), and its
lines are excluded from fail()/soft_warn() call-site extraction.

Deterministic and READ-ONLY: no writes, no test execution, no shelling out.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # keep the tool read-only: no .pyc writes into scripts/ on import

MIN_LITERAL_LEN = 12

# Aggregate disclosure row for top-level (outside-any-function) emit sites,
# which carry rule id "main" at runtime. See the module docstring.
MAIN_FLOW_NAME = "main"
MAIN_FLOW_STATUS = "MAIN-FLOW-AGGREGATE"

# Matches a top-level (column-0) bash function definition of the exact shape
# used throughout validate_docs.d and the adapter: `name() {` alone on a line.
_FUNC_START_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{\s*$")

# Matches a heredoc opener anywhere on a line: `<<`, optional `-` (tab-strip
# form), an optional matching quote around the delimiter word, and the word
# itself. Deliberately requires a bare identifier for the delimiter so a
# here-string (`<<< "$var"`) never matches (`$` is not a valid start char).
_HEREDOC_START_RE = re.compile(r"<<(-)?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")

# A fail()/soft_warn() call site: the function name as a whole word directly
# followed by whitespace and an opening double quote. Every real call site in
# this codebase is a single-argument, single-line, unescaped double-quoted
# string (verified against the current corpus); the extractor below is still
# defensive about a string that does not close on the same line.
_CALL_RE = re.compile(r"\b(fail|soft_warn)\s+\"")


class RuleFunction:
    __slots__ = ("name", "module", "file_rel", "start_line", "messages", "status", "matched_tests")

    def __init__(self, name: str, module: str, file_rel: str, start_line: int) -> None:
        self.name = name
        self.module = module
        self.file_rel = file_rel
        self.start_line = start_line
        self.messages: list[str] = []  # leading literal (before first '$') per emit site
        self.status = ""
        self.matched_tests: list[str] = []

    @property
    def messages_scanned(self) -> int:
        return len(self.messages)


def _default_project_root() -> Path:
    """Return the git repo that contains this script (the skill root).

    Deliberately independent of the docs-oriented root resolution used
    elsewhere in this package: that resolution can hop UP to a parent docs-SoR
    repo when the skill package has no docs/ dir of its own, which would land
    this tool outside the very scripts/ and tests/ trees it needs to read.
    This tool's root is always "the repo this script lives in."
    """
    script_dir = Path(__file__).resolve().parent
    try:
        result = subprocess.run(
            ["git", "-C", str(script_dir), "rev-parse", "--show-toplevel"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        top = result.stdout.strip()
        if top:
            return Path(top).resolve(strict=False)
    except (FileNotFoundError, subprocess.SubprocessError):
        pass
    return script_dir.parent  # scripts/ -> repo root fallback when git is unavailable


def _extract_quoted(line: str, start: int) -> str | None:
    """Return the double-quoted string content starting right after `start`.

    `start` is the index of the opening `"`. Returns None if the string does
    not close on this line (not expected in this codebase; handled so a
    stray multi-line literal cannot crash the scan).
    """
    i = start + 1
    out: list[str] = []
    while i < len(line):
        ch = line[i]
        if ch == "\\" and i + 1 < len(line):
            out.append(ch)
            out.append(line[i + 1])
            i += 2
            continue
        if ch == '"':
            return "".join(out)
        out.append(ch)
        i += 1
    return None


def _leading_literal(message: str) -> str:
    """Return the message text up to (not including) the first '$' expansion."""
    idx = message.find("$")
    return message if idx == -1 else message[:idx]


def parse_module_functions(path: Path, module: str, file_rel: str) -> tuple[list[RuleFunction], list[str]]:
    """Parse one shell file into its top-level (column-0) functions.

    State machine: outside a function, heredoc tracking, function-start
    detection, and TOP-LEVEL emit-site extraction run. Inside a function,
    every line is scanned for a heredoc opener (heredoc content is then
    skipped verbatim, including any column-0 `}` or `def foo():` it contains)
    and, once out of any heredoc, for the column-0 `}` that ends the
    function. fail()/soft_warn() call sites are only extracted from lines
    that were not inside a heredoc.

    Returns (functions, top_level_messages): the second element is the
    leading literal per fail()/soft_warn() call site found OUTSIDE any
    function (the runtime id="main" flow in the adapter).
    """
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.split("\n")

    functions: list[RuleFunction] = []
    top_level_messages: list[str] = []
    current: RuleFunction | None = None
    heredoc_delim: str | None = None
    heredoc_strip_tabs = False

    def record_emit_sites(raw: str, sink: list[str]) -> None:
        for call in _CALL_RE.finditer(raw):
            quote_start = call.end() - 1  # index of the opening '"'
            content = _extract_quoted(raw, quote_start)
            sink.append(_leading_literal(content) if content is not None else "")

    for lineno, raw in enumerate(lines, start=1):
        if heredoc_delim is not None:
            terminator = raw.lstrip("\t") if heredoc_strip_tabs else raw
            if terminator == heredoc_delim:
                heredoc_delim = None
            # Heredoc body lines (including this one, if it wasn't the
            # terminator) are opaque: never scanned for braces, function
            # starts, or emit sites.
            continue

        heredoc_match = _HEREDOC_START_RE.search(raw)

        if current is None:
            func_match = _FUNC_START_RE.match(raw)
            if func_match:
                current = RuleFunction(func_match.group(1), module, file_rel, lineno)
            else:
                record_emit_sites(raw, top_level_messages)
            if heredoc_match:
                heredoc_delim = heredoc_match.group(3)
                heredoc_strip_tabs = bool(heredoc_match.group(1))
            continue

        if raw.rstrip() == "}":
            functions.append(current)
            current = None
            continue

        record_emit_sites(raw, current.messages)

        if heredoc_match:
            heredoc_delim = heredoc_match.group(3)
            heredoc_strip_tabs = bool(heredoc_match.group(1))

    # A file ending mid-function is malformed input; nothing sane to record,
    # so the dangling function is silently dropped rather than fabricated.
    return functions, top_level_messages


def discover_module_files(project_root: Path) -> list[tuple[Path, str]]:
    """Return (path, module) pairs for validate_docs.d/*.sh plus the adapter."""
    scripts_dir = project_root / "scripts"
    pairs: list[tuple[Path, str]] = []

    rules_dir = scripts_dir / "validate_docs.d"
    if rules_dir.is_dir():
        for module_file in sorted(rules_dir.glob("*.sh")):
            pairs.append((module_file, module_file.stem))

    adapter = scripts_dir / "validate_docs.sh"
    if adapter.is_file():
        pairs.append((adapter, "adapter"))

    return pairs


def _distinctive_candidates(fn: RuleFunction, candidate_universe: dict[str, list[str]]) -> list[str]:
    """Return fn's literals that are long enough AND attributable to fn alone.

    A candidate is dropped as ambiguous when it appears as a substring of any
    OTHER rule's candidate (equal literals across two rules make both
    ambiguous). The reverse containment is fine: if fn's longer literal is
    found verbatim in a bats file, that match is distinctive for fn even when
    it happens to contain another rule's shorter prefix -- the other rule
    simply cannot use that shorter prefix itself.
    """
    own = candidate_universe.get(fn.name, [])
    distinctive: list[str] = []
    for candidate in own:
        ambiguous = any(
            candidate in other_candidate
            for other_name, other_candidates in candidate_universe.items()
            if other_name != fn.name
            for other_candidate in other_candidates
        )
        if not ambiguous:
            distinctive.append(candidate)
    return distinctive


def _matched_bats(distinctive: list[str], bats_contents: dict[str, str]) -> list[str]:
    return sorted(
        rel_name
        for rel_name, content in bats_contents.items()
        if any(candidate in content for candidate in distinctive)
    )


def classify(fn: RuleFunction, bats_contents: dict[str, str], candidate_universe: dict[str, list[str]]) -> None:
    """Classify a function from its emit-site literals against the bats corpus.

    TESTED requires a full-literal exact-substring match (a distinctive
    leading literal, in its entirety, is one contiguous substring of some
    bats file). This is intentionally strict rather than a fuzzy or
    partial-fragment search: an arbitrary-offset substring search (sliding
    min-length windows) was prototyped and rejected because generic domain
    words >= 12 chars (e.g. "orchestration") recur across unrelated bats
    files and produced false TESTED classifications -- worse for a
    coverage-gap tool than the accepted false negative below.

    Known heuristic gap (by design, not a bug): a bats assertion that
    wildcards from partway INTO a message's leading literal (skipping its
    first word(s), or truncating before its end) will not match here even
    though a human would call the rule tested. That imprecision is the
    accepted cost of a static, per-rule-annotation-free heuristic -- see the
    plan's stop conditions. UNTESTED and HEURISTIC-UNRESOLVED both mean "the
    heuristic found no strong signal," not "definitely no test exists."
    """
    if fn.status == MAIN_FLOW_STATUS:
        # Disclosure row: never TESTED/UNTESTED (see module docstring), but
        # matched tests are still reported for whatever distinctive literals
        # its sites have.
        fn.matched_tests = _matched_bats(_distinctive_candidates(fn, candidate_universe), bats_contents)
        return

    if not fn.messages:
        fn.status = "NO-EMIT"
        return

    if not any(len(m) >= MIN_LITERAL_LEN for m in fn.messages):
        fn.status = "HEURISTIC-UNRESOLVED"
        return

    distinctive = _distinctive_candidates(fn, candidate_universe)
    if not distinctive:
        # Long-enough literals exist but every one is ambiguous (shared with
        # another rule): no match can be attributed, so the rule is
        # heuristically unresolved -- never TESTED on unattributable text.
        fn.status = "HEURISTIC-UNRESOLVED"
        return

    matched = _matched_bats(distinctive, bats_contents)
    if matched:
        fn.status = "TESTED"
        fn.matched_tests = matched
    else:
        fn.status = "UNTESTED"


def collect_rules(project_root: Path) -> list[RuleFunction]:
    module_pairs = discover_module_files(project_root)

    bats_contents: dict[str, str] = {}
    tests_dir = project_root / "tests"
    if tests_dir.is_dir():
        for bats_file in sorted(tests_dir.glob("*.bats")):
            try:
                bats_contents[str(bats_file.relative_to(project_root))] = bats_file.read_text(
                    encoding="utf-8", errors="replace"
                )
            except OSError:
                continue

    rules: list[RuleFunction] = []
    main_flow: RuleFunction | None = None
    if module_pairs:
        # One aggregate disclosure row for all top-level (id="main") emit
        # sites; present whenever there is an inventory at all, so a zero
        # count is visible rather than indistinguishable from "not scanned".
        main_flow = RuleFunction(MAIN_FLOW_NAME, "adapter", "scripts/validate_docs.sh", 0)
        main_flow.status = MAIN_FLOW_STATUS

    for path, module in module_pairs:
        file_rel = str(path.relative_to(project_root))
        functions, top_level_messages = parse_module_functions(path, module, file_rel)
        rules.extend(functions)
        if main_flow is not None:
            main_flow.messages.extend(top_level_messages)

    if main_flow is not None:
        rules.append(main_flow)

    # The ambiguity universe spans ALL rows (functions and the main-flow
    # aggregate): a literal shared with the main flow is just as
    # unattributable as one shared with another function.
    candidate_universe = {
        fn.name: [m for m in fn.messages if len(m) >= MIN_LITERAL_LEN] for fn in rules
    }

    for fn in rules:
        classify(fn, bats_contents, candidate_universe)

    return rules


def render_text(rules: list[RuleFunction], project_root: Path) -> str:
    ordered = sorted(rules, key=lambda fn: (fn.module, fn.name))

    headers = ("MODULE", "FUNCTION", "STATUS", "MESSAGES", "MATCHED_TESTS")
    rows = [
        (
            fn.module,
            fn.name,
            fn.status,
            str(fn.messages_scanned),
            ",".join(fn.matched_tests) if fn.matched_tests else "-",
        )
        for fn in ordered
    ]
    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))

    def fmt_row(row: tuple[str, ...]) -> str:
        return "  ".join(cell.ljust(widths[i]) for i, cell in enumerate(row))

    lines = [f"# Validator Rule Coverage Report ({project_root})", ""]
    lines.append(fmt_row(headers))
    for row in rows:
        lines.append(fmt_row(row))

    counts = summary_counts(rules)
    lines.append("")
    lines.append(f"- total: {counts['total']}")
    for status in ("TESTED", "UNTESTED", "NO-EMIT", "HEURISTIC-UNRESOLVED", MAIN_FLOW_STATUS):
        lines.append(f"- {status}: {counts[status]}")
    lines.append(f"- main_flow_sites: {counts['main_flow_sites']}")

    return "\n".join(lines)


def summary_counts(rules: list[RuleFunction]) -> dict[str, int]:
    counts = {"TESTED": 0, "UNTESTED": 0, "NO-EMIT": 0, "HEURISTIC-UNRESOLVED": 0, MAIN_FLOW_STATUS: 0}
    main_flow_sites = 0
    for fn in rules:
        counts[fn.status] += 1
        if fn.status == MAIN_FLOW_STATUS:
            main_flow_sites += fn.messages_scanned
    counts["total"] = len(rules)
    counts["main_flow_sites"] = main_flow_sites
    return counts


def render_json(rules: list[RuleFunction], project_root: Path) -> str:
    ordered = sorted(rules, key=lambda fn: (fn.module, fn.name))
    payload = {
        "tool": "validator_rule_coverage",
        "format_version": 1,
        "project_root": str(project_root),
        "rules": [
            {
                "function": fn.name,
                "module": fn.module,
                "status": fn.status,
                "matched_tests": fn.matched_tests,
                "messages_scanned": fn.messages_scanned,
            }
            for fn in ordered
        ],
        "summary": summary_counts(rules),
    }
    return json.dumps(payload)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Read-only validator rule <-> test coverage matrix.")
    parser.add_argument(
        "--project-root",
        help="Skill root containing scripts/ and tests/ (default: the git repo containing this script).",
    )
    parser.add_argument("--format", choices=["text", "json"], default="text", help="Output format (default: text).")
    parser.add_argument(
        "--exit-code",
        action="store_true",
        help=(
            "Exit 1 if any rule function is UNTESTED (default off; for future CI use). "
            "The main-flow disclosure row never triggers this."
        ),
    )
    args = parser.parse_args(argv)

    project_root = (
        Path(args.project_root).expanduser().resolve(strict=False) if args.project_root else _default_project_root()
    )

    rules = collect_rules(project_root)

    if args.format == "json":
        print(render_json(rules, project_root))
    else:
        print(render_text(rules, project_root))

    if args.exit_code and any(fn.status == "UNTESTED" for fn in rules):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
