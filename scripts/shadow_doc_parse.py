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
from pathlib import Path

FENCE_CHARS = (chr(96), "~")


def split_lines(text: str):
    r"""Split a document into lines the way every other reader of it does: on `\n` only.

    This is the second half of the shared answer, and it was missing. `str.splitlines()`
    also breaks on VT, FF, FS, GS, RS, NEL, U+2028 and U+2029; `grep`, `awk`, `sed`,
    `wc -l` and `while read` break on `\n` alone. Routing every `- key:` reader through a
    splitlines-derived copy therefore changed what a LINE is, and the two arrangements of
    a single form feed answer in OPPOSITE directions (the task
    r03 finding 1): with the control character in a non-matching prefix the split copy
    finds a field the raw grep does not, and with it inside a matching line the split copy
    truncates a value the raw grep returns whole.

    CommonMark decides which side moves rather than which answer looks tidier: "a line is
    a sequence of zero or more characters other than line feed or carriage return,
    followed by a line ending". A form feed is not a line ending, so on BOTH arrangements
    the `\n` answer is the one a markdown renderer produces.

    A `\r` is KEPT rather than dropped, for the same reason: `grep` keeps it, so a reader
    that drops it is a reader that disagrees. `fence_marker` and the field patterns here
    tolerate a trailing CR already (`lstrip` / `\s*$`).

    That sentence was TRUE of this function and FALSE of the tree, because `read_lines`
    below handed it text that no longer had a `\r` in it -- see there. Corpus measurement,
    restated correctly: of the 870 markdown files in this repo, 0 carry any of the eight
    extra `splitlines` break characters and 12 carry a CR. All twelve are CRLF (no lone
    CR anywhere), all twelve sit under `codeguide/references/`, and 0 sit under `docs/`,
    which is why the finding was latent rather than absent. `core.autocrlf=input` hides
    them from `git status`, so "the tree is clean" is not evidence about this axis.
    """
    if not text:
        return []
    if text.endswith("\n"):
        text = text[:-1]
    return text.split("\n")


def read_document_text(path, errors: str = "replace") -> str:
    r"""Decode a document's bytes with NO newline translation.

    `Path.read_text` opens in universal-newline mode: CRLF and a lone CR are already `\n`
    by the time any splitter runs. So `read_lines` used to promise the CR rule above and
    break it one line later, and the promise was unfalsifiable from inside python -- the
    only way to see it is to compare against `grep`, `sed` or the bytes on disk
    (the task r01 finding 1).

    That was not merely a wrong docstring. `codeguide_doc_lines.require_unfenced_field_line`
    turns this reader's index into a `sed` ADDRESS, and `sed` splits on `\n` alone: one
    stray CR above a field shifted the address by one, so an upsert silently edited the
    wrong line -- or a FENCED example -- while the tool exited 0 (r01 finding 2). A line
    NUMBER is the one thing that cannot tolerate two definitions of a line.

    `read_bytes().decode(...)` rather than `read_text(..., newline="")` because
    `pathlib.Path.read_text` has no `newline` parameter before Python 3.13 and the scripts
    contract runs on 3.11 -- verified, not assumed: on this interpreter the signature is
    `(self, encoding=None, errors=None)` and passing `newline` raises TypeError.
    """
    return Path(path).read_bytes().decode("utf-8", errors=errors)


def read_lines(path):
    r"""Read a document from disk and split it with the one line rule above.

    Every caller used to write `path.read_text(...).splitlines()` for itself, which is
    where the divergence entered: the fence rule was shared and the line rule was not.
    The read is byte-faithful (see read_document_text) so the line rule survives the read.
    """
    return split_lines(read_document_text(path))


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


def _fence_walk(lines):
    """The one fence state machine: yield (kind, index, line) for every input line.

    kind is "content" outside any block, "open"/"close" for the markers that delimit one,
    and "inside" for a line within a block (including a non-closing marker). Every
    fence-aware view below is built on this and on nothing else. Three near-identical
    copies of these six lines existed before -- content_lines, scan, and a private one in
    shadow_source_digest that kept line INDICES -- which is exactly the shape that let
    `~~~`-inside-``` drift between six readers in the first place
    (the recorded decision).

    A block closes only on a marker of the SAME character and at least the opener's
    length (CommonMark): a shorter or different marker inside the block is content, and
    an unterminated fence runs to end of document, matching a markdown renderer. That is
    what `shadow_metrics_report.py` already did and what the first cut of this module got
    wrong -- toggling on any marker let a `~~~` line inside a ``` block flip the state,
    which both leaked example lines out of a fence and, worse, swallowed a real dangling
    reference so the rule printed PASS.
    """
    open_char = None
    open_len = 0
    for index, line in enumerate(lines):
        marker = fence_marker(line)
        if open_char is None:
            if marker is not None:
                open_char, open_len = marker
                yield "open", index, line
                continue
            yield "content", index, line
            continue
        if marker is not None and marker[0] == open_char and marker[1] >= open_len:
            open_char, open_len = None, 0
            yield "close", index, line
            continue
        yield "inside", index, line


def content_lines(lines):
    """Yield the lines OUTSIDE fenced blocks, fence markers excluded."""
    for kind, _, line in _fence_walk(lines):
        if kind == "content":
            yield line


def numbered_content_lines(lines):
    """content_lines with the 0-based index of each line in the ORIGINAL document.

    For callers that must ADDRESS a line rather than only read it -- both shell writers of
    the docs capsules (doc_garden.sh and run_external_plan_reviews.sh, through the one
    adapter codeguide_doc_lines.sh) edit the first unfenced `- key:` line with a
    line-addressed `sed`, because an unaddressed one rewrote a fenced template example as
    if it were the real field (the task r03 finding 2). A writer
    needs the number, and it must be the number the shared fence rule produces -- from the
    same BYTES `sed` will count, which is why read_document_text exists.
    """
    for kind, index, line in _fence_walk(lines):
        if kind == "content":
            yield index, line


def ends_inside_fence(lines) -> bool:
    """True when the document ends inside an UNTERMINATED fenced block.

    Only a writer needs this, and it needs it to refuse rather than to guess: appending
    `- key: value` to such a document puts the field inside the block, where no reader can
    see it, so the next run appends again and the capsule grows without bound
    (the task r01 finding 5). Public rather than a second walk in
    the caller: the state at end of input belongs to the state machine that produced it.
    """
    kind = "content"
    for kind, _, _ in _fence_walk(lines):
        pass
    return kind in ("open", "inside")


def scan(lines):
    """Yield ("content", line) and ("boundary", None) using the same fence rule.

    For readers that track state ACROSS lines (a field header whose members follow):
    they need to know a fence boundary happened so a bullet after the block is never
    attributed to a header before it, which content_lines() alone cannot tell them.
    """
    for kind, _, line in _fence_walk(lines):
        if kind == "content":
            yield "content", line
        elif kind in ("open", "close"):
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
