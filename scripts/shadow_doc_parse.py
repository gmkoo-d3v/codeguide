#!/usr/bin/env python3
"""Shared reader for shadow documents: what is a fence, and what is a field value.

Every shadow rule used to answer these two questions for itself, and the answers
drifted: three readers treated `~~~` as a fence while three treated it as content,
so a tilde-fenced template example was an example to one rule and a dangling
reference to another (the recorded decision). One line, two verdicts,
decided by which rule happened to read it — indistinguishable at the gate from a
real defect.

This module is the single answer. It is stdlib-only (scripts contract) and holds
no policy: callers still decide what a finding is, what tier it carries, and what
it says. It carries only what a caller actually uses -- field readers with no
consumer were removed rather than shipped as speculative surface. Deliberately NOT
in scope: the effect-map and policy-registry grammars, which parse different
documents with their own evidence rules, and check_tmp_path_references, which scans
task/plan/orchestration docs rather than shadow docs.

Fence rule: a line opens or closes a fenced block when its stripped form starts
with three backticks or three tildes. That is the union of the previous behaviors,
chosen because the tilde-blind readers were the ones producing false positives.
"""
from __future__ import annotations

import re

FENCE_CHARS = (chr(96), "~")


def fence_marker(line: str):
    """Return (char, run-length) when the line is a fence marker, else None."""
    stripped = line.lstrip()
    for char in FENCE_CHARS:
        if stripped.startswith(char * 3):
            return char, len(stripped) - len(stripped.lstrip(char))
    return None


def is_fence(line: str) -> bool:
    """True when the line is a fence marker of either flavour.

    Kept as the readable predicate for callers that only need "is this a marker".
    Anything tracking fence STATE must use content_lines() or scan(): a marker is not
    automatically a closer, and treating it as one is the defect this module fixes.
    """
    return fence_marker(line) is not None


def content_lines(lines):
    """Yield the lines OUTSIDE fenced blocks, fence markers excluded.

    A block closes only on a marker of the SAME character and at least the opener's
    length (CommonMark), which is what `shadow_metrics_report.py` already did and what
    the first cut of this module got wrong: toggling on any marker let a `~~~` line
    inside a ``` block flip the state, which both leaked example lines out of a fence
    and — worse — swallowed a real dangling reference so the rule printed PASS.
    An unterminated fence runs to end of document, matching a markdown renderer.
    """
    open_char = None
    open_len = 0
    for line in lines:
        marker = fence_marker(line)
        if open_char is None:
            if marker is not None:
                open_char, open_len = marker
                continue
            yield line
            continue
        if marker is not None and marker[0] == open_char and marker[1] >= open_len:
            open_char, open_len = None, 0
        # every line inside the block, including a non-closing marker, is content


def scan(lines):
    """Yield ("content", line) and ("boundary", None) using the same fence rule.

    For readers that track state ACROSS lines (a field header whose members follow):
    they need to know a fence boundary happened so a bullet after the block is never
    attributed to a header before it, which content_lines() alone cannot tell them.
    """
    open_char = None
    open_len = 0
    for line in lines:
        marker = fence_marker(line)
        if open_char is None:
            if marker is not None:
                open_char, open_len = marker
                yield "boundary", None
                continue
            yield "content", line
            continue
        if marker is not None and marker[0] == open_char and marker[1] >= open_len:
            open_char, open_len = None, 0
            yield "boundary", None


def _inline_re(key: str) -> re.Pattern:
    return re.compile(r"^\s*-\s*" + re.escape(key) + r"\s*:\s*(\S.*?)\s*$")


def _header_re(key: str) -> re.Pattern:
    return re.compile(r"^(\s*)-\s*" + re.escape(key) + r"\s*:\s*$")


_BULLET_RE = re.compile(r"^(\s*)-\s+(\S.*?)\s*$")


def field_value(lines, key: str) -> str:
    """First non-empty inline value for `- key:` outside fences.

    Indentation is tolerated so an indented carrier is surfaced rather than skipped,
    and an empty stub is passed over in favour of a later real value. A second
    occurrence is ignored by design: the first non-empty one wins.
    """
    pattern = _inline_re(key)
    for line in content_lines(lines):
        match = pattern.match(line)
        if match:
            return match.group(1).strip()
    return ""
