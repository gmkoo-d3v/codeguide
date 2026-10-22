#!/usr/bin/env python3
"""Verify the evidence set behind ONE required external-review route.

Called by validate_docs.d/40-rules-orchestration.sh (await_gate_route_has_accept_artifact)
for every route listed in ORCH `required_review_routes` once the external-review await
gate has resolved the round directory.

A route only counts as accepted when the directory holds a complete, internally
consistent, wrapper-generated evidence set for it -- not merely a markdown file
containing `verdict: accept`. Two sets are recognised, the ones
run_external_plan_reviews.sh writes:

  first attempt   <slug>.request.md        <slug>.response.md        <slug>.response.provenance.md
  retry attempt   <slug>.retry-request.md  <slug>.retry-response.md  <slug>.retry-response.provenance.md

where <slug> is the route with every character outside [A-Za-z0-9._-] replaced by `-`.
The route is satisfied when ANY recognised set verifies completely. For the set it checks:

  response    non-empty, `verdict: accept`, every parser-compatible review field the
              wrapper itself requires. Standard: summary/strengths/risks/requested_changes,
              all non-empty. Adversarial adds objection/counterproposal/rebuttal/residual_risk
              under the contract's adversarial field rule (references/
              orchestration-review-contract.md), the same rule run_external_plan_reviews.sh
              and the Shadow v2 close gate apply: all four KEYS must be present on every
              verdict (a missing key is malformed); residual_risk must be non-empty on every
              verdict; objection/counterproposal/rebuttal must be non-empty except on accept,
              where a present-but-empty value is the coherent "nothing to object to" answer
  request     present; task_id / plan_version / review_round / evaluator (== route) match;
              sanitized_response_file, expected_response_file and command_response_path
              name this very response / raw-capture file
  provenance  present; artifact_kind and generated_by are the wrapper's; task_id,
              plan_version, review_round match the consumed plan and round; requested and
              actual route both equal the required route and no quota fallback happened;
              verdict is accept and equals the response's; request_file / response_file /
              command_response_path name the companion files; raw_capture_deleted and
              sanitized_response are true; response_sha256 equals the SHA-256 recomputed
              from the response file's bytes right now

Recorded paths are compared by their TAIL (<task>/external-cli/<plan-version>/<round>/<file>,
or just the file name when the manifest recorded a bare name). The wrapper records absolute
paths, so exact comparison would reject genuine artifacts the moment a project is moved,
cloned or checked out into a worktree; the tail still pins task, plan version, round and
file.

This is CONSISTENCY evidence, not tamper-proof attestation (see
references/external-cli-handoff.md): in a writable workspace someone can still forge a
matching response/request/provenance triple, hash included. What it does reject is every
cheaper shortcut -- a bare accept file, a hand-written manifest, an edited response, a
manifest copied from another task/plan/round/route, an incomplete review the wrapper itself
refused.

With --verdict-only it reproduces the pre-hardening behaviour (any recognised response file
whose `verdict:` is accept). The validator keeps that tier only for terminal (done) tasks,
whose evidence is immutable history and is not re-measured against rules introduced after
they closed -- the same precedent as the orchestration size cap.

Usage:
  validate_docs_review_evidence.py [--verdict-only] <result_dir> <route> <task_id> <plan_version> <review_round>

Exit status: 0 verified (stdout empty), 1 rejected (one reason per line on stdout), 2 usage.
Read-only: never writes anything.
"""
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # read-only tool: no .pyc into scripts/

ARTIFACT_KIND = "external_cli_review_response_provenance"
GENERATED_BY = "run_external_plan_reviews.sh"
STANDARD_FIELDS = ("summary", "strengths", "risks", "requested_changes")
ADVERSARIAL_FIELDS = ("objection", "counterproposal", "rebuttal", "residual_risk")
# The only adversarial value that may be empty, and only on accept; residual_risk never may.
ADVERSARIAL_DEBATE_FIELDS = ("objection", "counterproposal", "rebuttal")


def route_slug(route: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]", "-", route)


def field(text: str, key: str) -> str | None:
    """First column-0 `- key: value` line, the grammar the wrapper's own parser uses."""
    match = re.search(rf"(?m)^- {re.escape(key)}:[ \t]*(.*)$", text)
    if match is None:
        return None
    return " ".join(match.group(1).split())


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def sha256_ref(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def tail_matches(recorded: str | None, expected_parts: tuple[str, ...]) -> bool:
    if not recorded:
        return False
    parts = tuple(part for part in recorded.replace("\\", "/").split("/") if part not in ("", "."))
    if not parts:
        return False
    count = min(len(parts), len(expected_parts))
    return parts[-count:] == expected_parts[-count:]


def regular_file(path: Path) -> bool:
    return path.is_file() and not path.is_symlink()


def candidates(slug: str) -> tuple[dict[str, str], ...]:
    return (
        {
            "label": "response",
            "response": f"{slug}.response.md",
            "request": f"{slug}.request.md",
            "provenance": f"{slug}.response.provenance.md",
            "raw": f"{slug}.command-response.raw.md",
        },
        {
            "label": "retry-response",
            "response": f"{slug}.retry-response.md",
            "request": f"{slug}.retry-request.md",
            "provenance": f"{slug}.retry-response.provenance.md",
            "raw": f"{slug}.retry-command-response.raw.md",
        },
    )


def verify_set(
    names: dict[str, str],
    result_dir: Path,
    route: str,
    task_id: str,
    plan_version: str,
    review_round: str,
) -> list[str]:
    problems: list[str] = []
    response_path = result_dir / names["response"]
    request_path = result_dir / names["request"]
    provenance_path = result_dir / names["provenance"]
    raw_path = result_dir / names["raw"]
    tail_base = (task_id, "external-cli", plan_version, review_round)
    response_tail = tail_base + (names["response"],)
    request_tail = tail_base + (names["request"],)
    raw_tail = tail_base + (names["raw"],)

    if response_path.is_symlink():
        return [f"response {names['response']} is a symlink, not a regular file"]
    response_text = read(response_path)
    if not response_text.strip():
        return [f"response {names['response']} is empty"]

    verdict = (field(response_text, "verdict") or "").lower()
    if verdict != "accept":
        problems.append(f"response verdict is '{verdict or 'missing'}', expected accept")

    # --- provenance (read first: it decides whether adversarial fields are required) ---
    provenance_text = ""
    review_style = ""
    if not regular_file(provenance_path):
        problems.append(f"provenance manifest is missing: {names['provenance']}")
    else:
        provenance_text = read(provenance_path)
        if not provenance_text.strip():
            problems.append(f"provenance manifest is empty: {names['provenance']}")
            provenance_text = ""
    if provenance_text:
        review_style = (field(provenance_text, "review_style") or "").lower()

        def expect(key: str, wanted: str, label: str = "provenance") -> None:
            got = field(provenance_text, key)
            if got != wanted:
                problems.append(f"{label} {key} is '{got if got is not None else 'missing'}', expected '{wanted}'")

        expect("artifact_kind", ARTIFACT_KIND)
        expect("generated_by", GENERATED_BY)
        expect("task_id", task_id)
        expect("plan_version", plan_version)
        expect("review_round", review_round)
        expect("evaluator_requested_route", route)
        expect("evaluator_actual_route", route)
        expect("quota_fallback_triggered", "false")
        expect("raw_capture_deleted", "true")
        expect("sanitized_response", "true")
        if review_style not in ("standard", "adversarial"):
            problems.append(f"provenance review_style is '{review_style or 'missing'}', expected standard or adversarial")
        provenance_verdict = (field(provenance_text, "verdict") or "").lower()
        if provenance_verdict != "accept":
            problems.append(f"provenance verdict is '{provenance_verdict or 'missing'}', expected 'accept'")
        elif verdict and provenance_verdict != verdict:
            problems.append(f"provenance verdict '{provenance_verdict}' disagrees with the response verdict '{verdict}'")

        recorded_hash = field(provenance_text, "response_sha256")
        if not recorded_hash:
            problems.append("provenance response_sha256 is missing")
        elif recorded_hash != sha256_ref(response_path):
            problems.append(
                "provenance response_sha256 does not match the response file (edited, truncated or replaced after the wrapper hashed it)"
            )
        if not tail_matches(field(provenance_text, "response_file"), response_tail):
            problems.append(f"provenance response_file does not name {names['response']} of this round")
        if not tail_matches(field(provenance_text, "request_file"), request_tail):
            problems.append(f"provenance request_file does not name {names['request']} of this round")
        if not tail_matches(field(provenance_text, "command_response_path"), raw_tail):
            problems.append(f"provenance command_response_path does not name {names['raw']} of this round")

    # --- response fields: the same rules run_external_plan_reviews.sh applies when it parses ---
    for key in STANDARD_FIELDS:
        if not field(response_text, key):
            problems.append(f"response is missing required review field {key}")
    if review_style == "adversarial":
        # field() separates "key absent" (None) from "key present, value empty" ("").
        for key in ADVERSARIAL_FIELDS:
            value = field(response_text, key)
            if value is None:
                problems.append(f"response is missing required review field {key}")
            elif not value and (key not in ADVERSARIAL_DEBATE_FIELDS or verdict != "accept"):
                problems.append(f"response has an empty required review field {key}")

    # --- companion request ---
    if not regular_file(request_path):
        problems.append(f"companion request file is missing: {names['request']}")
    else:
        request_text = read(request_path)
        if not request_text.strip():
            problems.append(f"companion request file is empty: {names['request']}")
        else:
            for key, wanted in (
                ("task_id", task_id),
                ("plan_version", plan_version),
                ("review_round", review_round),
                ("evaluator", route),
            ):
                got = field(request_text, key)
                if got != wanted:
                    problems.append(f"request {key} is '{got if got is not None else 'missing'}', expected '{wanted}'")
            if review_style and field(request_text, "review_style") != review_style:
                problems.append("request review_style disagrees with the provenance review_style")
            for key, tail, label in (
                ("sanitized_response_file", response_tail, names["response"]),
                ("expected_response_file", response_tail, names["response"]),
                ("command_response_path", raw_tail, names["raw"]),
            ):
                if not tail_matches(field(request_text, key), tail):
                    problems.append(f"request {key} does not name {label} of this round")

    if raw_path.exists():
        problems.append(f"raw command capture still exists beside the sanitized response: {names['raw']}")
    return problems


def main(argv: list[str]) -> int:
    verdict_only = False
    args = argv[1:]
    if args and args[0] == "--verdict-only":
        verdict_only = True
        args = args[1:]
    if len(args) != 5:
        print(__doc__.split("Usage:")[1].split("Exit status")[0].strip(), file=sys.stderr)
        return 2
    result_dir, route, task_id, plan_version, review_round = args
    directory = Path(result_dir)
    slug = route_slug(route)
    sets = candidates(slug)

    present = [names for names in sets if (directory / names["response"]).is_file() or (directory / names["response"]).is_symlink()]
    if not present:
        print(f"no response artifact ({sets[0]['response']} or {sets[1]['response']}) in the round directory")
        return 1

    if verdict_only:
        for names in present:
            text = read(directory / names["response"])
            if (field(text, "verdict") or "") == "accept":
                return 0
        print("no recognised response file carries verdict: accept")
        return 1

    all_problems: list[str] = []
    for names in present:
        problems = verify_set(names, directory, route, task_id, plan_version, review_round)
        if not problems:
            return 0
        prefix = f"[{names['label']}] " if len(present) > 1 else ""
        all_problems.extend(prefix + problem for problem in problems)
    for problem in all_problems:
        print(problem)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
