# codeguide_doc_lines.sh -- the ONE shell adapter over the shared document reader.
# Sourced (never executed) by every shell tool that WRITES a docs capsule: doc_garden.sh
# and run_external_plan_reviews.sh. Requires CODEGUIDE_DOC_LINES_SCRIPT_DIR, or falls back
# to this file's own directory, to locate shadow_doc_parse.py.
#
# Why a shared file rather than a copy per tool: two shell tools EDIT the same
# task/plan/orchestration capsules the validator reads, and each answered "where is the
# real `- key:` line" for itself with a fence-blind `grep -qE "^- ${key}:"` plus a `sed`
# with NO line address, so each replaced EVERY match including one inside a fenced template
# example (the task r03 finding 2, reproduced on both). A writer
# that answers this question differently from the reader is strictly worse than a reader
# that does, because it EDITS its answer -- and a second private copy of the adapter is how
# the first divergence got here.
#
# unfenced_lines prints 1-based line NUMBERS, one per line, or nothing when nothing matches.
# Every write addressed by one of these numbers requires python and `sed` to count lines
# identically -- `shadow_doc_parse.read_lines` reads the BYTES on disk for exactly that
# reason (the task r01 finding 2: while it read through
# `Path.read_text`, whose universal-newline mode turns CRLF and a lone CR into `\n`, one
# stray CR shifted every address below it by one, and an upsert silently edited the wrong
# line -- or a fenced example -- while the tool exited 0).
#
# Modes, all LITERAL rather than regex, each chosen to match the reader it must agree with:
#   prefix     - `str.startswith`, the same answer as the validator's `grep -E "^- key:"`
#                for every key these tools write (all code literals, no ERE metacharacter),
#                and a safer one if that stops being true.
#   exact      - whole-line equality, the awk `$0 == section` the index inserters use.
#   substring  - `literal in line`, the `grep -F` the index row deleters use. Same rule as
#                before, one axis narrower: fenced lines no longer count.
#   open-fence - prints 1 when the document ENDS inside an unterminated fence, else nothing.
#
# Unlike the validator's read path, a failure here is LOUD (require_unfenced_lines): the
# read side degrades to the original document on purpose, which merely misreports, while a
# write that guessed wrong would corrupt a capsule.

codeguide_doc_lines_script_dir() {
  if [[ -n "${CODEGUIDE_DOC_LINES_SCRIPT_DIR:-}" ]]; then
    printf "%s" "$CODEGUIDE_DOC_LINES_SCRIPT_DIR"
    return 0
  fi
  (cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
}

unfenced_lines() {
  local file_path="$1"
  local mode="$2"
  local literal="$3"
  local script_dir

  [[ -f "$file_path" ]] || return 0
  script_dir="$(codeguide_doc_lines_script_dir)"
  python3 - "$file_path" "$mode" "$literal" "$script_dir" <<'FIELDLINE'
import sys
import os

# Drop the CALLER'S WORKING DIRECTORY from the import path before adding the script dir.
# `python3 -` puts "" (cwd) at sys.path[0], so which `shadow_doc_parse` this writer obeys
# depended on where the user happened to `cd` -- the script dir wins only when the module is
# present there, and when it is NOT, cwd answers instead. That is the same defect this whole
# adapter exists to end (one document, two answers, decided by something incidental), and it
# is worse in a writer: running doc_garden from a directory holding an OLDER or FOREIGN
# shadow_doc_parse.py would silently edit by that copy's fence rule. Reproduced by running
# check_all.sh from `scripts/`, where the "reader unavailable" fixture stopped failing
# because cwd supplied the module the fixture had deliberately removed.
#
# F12: the parser is required BESIDE the adapter, and the imported module must BE that
# exact file. A partial deployment (local parser missing) or a PYTHONPATH-substituted
# foreign/stale parser must fail loudly instead of reading by the wrong fence grammar.
local_parser = os.path.join(sys.argv[4], "shadow_doc_parse.py")
if not os.path.isfile(local_parser):
    sys.stderr.write("[ERROR] Shared fence reader requires the local parser beside the adapter: " + local_parser + "\n")
    raise SystemExit(2)
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
sys.path.insert(0, sys.argv[4])
sys.dont_write_bytecode = True
import shadow_doc_parse

if os.path.realpath(os.path.abspath(shadow_doc_parse.__file__)) != os.path.realpath(local_parser):
    sys.stderr.write("[ERROR] Shared fence reader imported a foreign shadow_doc_parse from "
                     + os.path.realpath(os.path.abspath(shadow_doc_parse.__file__))
                     + "; required local parser: " + os.path.realpath(local_parser) + "\n")
    raise SystemExit(2)

path, mode, literal = sys.argv[1], sys.argv[2], sys.argv[3]
lines = shadow_doc_parse.read_lines(path)

if mode == "open-fence":
    if shadow_doc_parse.ends_inside_fence(lines):
        sys.stdout.write("1")
    raise SystemExit(0)

if mode == "prefix":
    def hit(line):
        return line.startswith(literal)
elif mode == "exact":
    def hit(line):
        return line == literal
elif mode == "substring":
    def hit(line):
        return literal in line
else:
    sys.stderr.write("unknown mode: " + mode + "\n")
    raise SystemExit(2)

out = [str(index + 1) for index, line in shadow_doc_parse.numbered_content_lines(lines) if hit(line)]
if out:
    sys.stdout.write("\n".join(out))
FIELDLINE
}

# The loud half. It is a plain function call, never a command substitution, so its `exit`
# leaves the SAME shell the caller is in.
#
# Exactly ONE command substitution may sit between a caller in the main shell and this
# `exit`, and every `require_*` below therefore calls `unfenced_lines` directly instead of
# layering. The MECHANISM, measured rather than inferred (the task
# r02 finding 2 and the fix round's own measurement): on bash 3.2.57, the version the
# scripts contract targets, `set -e` is NOT INHERITED by a command-substitution subshell --
# `$-` inside `$( ... )` is `hBc` where the parent's is `ehBc`. So the `exit` below leaves
# only its own subshell, and the enclosing shell notices exclusively through `set -e` on
# the failed assignment, which exists only in the MAIN shell. `v="$(mid)"` where `mid` runs
# `out="$(inner)"` and `inner` exits 1 leaves v empty, prints nothing, and CONTINUES.
# Stacking two wrappers here turned the loud refusal into a silent empty line number, which
# sends every upsert down the APPEND branch and duplicates the whole capsule metadata block.
#
# The consequence is stronger than "keep the wrappers flat", and it is why
# require_shared_reader below exists: a per-call-site depth rule CANNOT be made to hold for
# a caller that is itself inside a substitution. `run_external_plan_reviews.high_risk_source_for_task`
# is invoked as `HIGH_RISK_SOURCE="$(high_risk_source_for_task || true)"`, so every capsule
# read inside it is two deep no matter how those reads are written -- flattening them still
# left the adversarial-review gate silently waived (measured against a flattened build).
# Depth discipline is therefore necessary and not sufficient, and the preflight is the half
# that holds regardless of depth.
codeguide_doc_lines_fail() {
  echo "[ERROR] Could not read ${1} with the shared fence reader; refusing to edit it" >&2
  exit 1
}

# The depth-independent half: assert ONCE, from the main shell, that the shared reader can
# actually be loaded, before any document is read or written.
#
# Every other refusal in this adapter is observable only one substitution deep (see above),
# and the condition that produces essentially all of them -- python3 missing, or
# shadow_doc_parse.py not beside the adapter -- is a property of the RUN, not of a document.
# Checking it once where `set -e` is in force converts an invariant that must be re-proved
# at every future call site into a single assertion no call site can undermine. Per-file
# read failures (an unreadable path, a python crash on one document) still rely on the depth
# rule; that residual is recorded in the PLAN rather than hidden here.
#
# Callers invoke this as a plain command in the main shell -- never `$( ... )`, never
# `if require_shared_reader`, both of which would put it back in a context where the `exit`
# cannot reach the caller.
require_shared_reader() {
  local script_dir
  script_dir="$(codeguide_doc_lines_script_dir)"
  python3 - "$script_dir" <<'READERPROBE' 2>/dev/null && return 0
import sys
import os

# Same import path as unfenced_lines, cwd dropped for the same reason -- see there. A
# preflight that resolved the module differently from the reads it stands in for would be
# worse than no preflight: it would certify a reader the actual reads never use.
#
# F12 (same rule as unfenced_lines): the parser must exist beside the adapter and the
# imported module must BE that exact file, so a missing local parser or a
# PYTHONPATH-substituted foreign/stale parser fails this preflight loudly.
local_parser = os.path.join(sys.argv[1], "shadow_doc_parse.py")
if not os.path.isfile(local_parser):
    sys.stderr.write("[ERROR] Shared fence reader requires the local parser beside the adapter: " + local_parser + "\n")
    raise SystemExit(2)
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
sys.path.insert(0, sys.argv[1])
sys.dont_write_bytecode = True
import shadow_doc_parse

if os.path.realpath(os.path.abspath(shadow_doc_parse.__file__)) != os.path.realpath(local_parser):
    sys.stderr.write("[ERROR] Shared fence reader imported a foreign shadow_doc_parse from "
                     + os.path.realpath(os.path.abspath(shadow_doc_parse.__file__))
                     + "; required local parser: " + os.path.realpath(local_parser) + "\n")
    raise SystemExit(2)

for name in ("read_lines", "numbered_content_lines", "ends_inside_fence"):
    getattr(shadow_doc_parse, name)
READERPROBE
  echo "[ERROR] Could not read documents with the shared fence reader; refusing to edit any of them (shadow_doc_parse.py not loadable from ${script_dir}, or a foreign copy was substituted)" >&2
  exit 1
}

# Refuse to APPEND to a document that ends inside an UNTERMINATED fenced block.
#
# Appending puts the new line inside that block, where the next lookup cannot see it, so the
# run after this one appends again and the document grows without bound. This guard was
# fitted to the FIELD writer and to neither ROW writer, and the row half is the unbounded
# one: three `doc_garden.sh` runs took a decision-index from 10 lines to 31 with
# `grep -c '^## Accepted'` going 1 to 4, three live rows inside the fence, exit 0 each time,
# and the validator then reported all three rows missing -- and a later status change
# APPENDED a second task-index row instead of replacing the first, because the fence-aware
# delete cannot see the row the fence-blind append wrote (r02 finding 1, reproduced end to
# end before this hoist). One guard, one place, every appender.
#
# $3 is the path to NAME in the diagnostic when the file being appended to is a working copy:
# `ensure_decision_index_sections` appends to a `mktemp` copy and moves it into place, and an
# error naming `/var/folders/.../tmp.XYZ` tells the author nothing about which document to go
# close a fence in.
#
# Assigned first, never `[[ -n "$( ... )" ]]`: a `[[ ]]` condition swallows the reader failure
# outright, which would turn the loud refusal into "no open fence". A missing file is
# appendable by definition -- the append CREATES it.
require_appendable() {
  local file_path="$1"
  local what="$2"
  local display_path="${3:-$1}"
  local open_fence

  if [[ ! -f "$file_path" ]]; then
    return 0
  fi
  open_fence="$(unfenced_lines "$file_path" open-fence "")" || codeguide_doc_lines_fail "$display_path"
  if [[ -n "$open_fence" ]]; then
    echo "[ERROR] ${display_path} ends inside an unterminated fenced block; refusing to append ${what} (close the fence first)" >&2
    exit 1
  fi
}

require_unfenced_lines() {
  local out
  out="$(unfenced_lines "$1" "$2" "$3")" || codeguide_doc_lines_fail "$1"
  printf "%s" "$out"
}

# First unfenced line only -- `${out%%<newline>*}` rather than a pipe, so the exit status
# of the read (and therefore the loud failure above) is not swallowed by `head`.
require_first_unfenced_line() {
  local out
  out="$(unfenced_lines "$1" "$2" "$3")" || codeguide_doc_lines_fail "$1"
  printf "%s" "${out%%$'\n'*}"
}

# The 1-based line number of the first REAL `- key:` line -- the one extract_field_value
# reads. Empty when the key has no unfenced occurrence.
require_unfenced_field_line() {
  local out
  out="$(unfenced_lines "$1" prefix "- ${2}:")" || codeguide_doc_lines_fail "$1"
  printf "%s" "${out%%$'\n'*}"
}

# The value of that same line, with the same prefix strip extract_field_value uses. The
# private `grep | head -n 1 | sed` this replaces was the reader HALF of the writer, and it
# was fence-blind while the write became fence-aware -- which would have been a new
# divergence inside one function rather than a fix.
unfenced_field_value() {
  local file_path="$1"
  local key="$2"
  local line_no

  line_no="$(unfenced_lines "$file_path" prefix "- ${key}:")" || codeguide_doc_lines_fail "$file_path"
  line_no="${line_no%%$'\n'*}"
  [[ -n "$line_no" ]] || return 0
  sed -n "${line_no}p" "$file_path" | sed "s/^- ${key}:[[:space:]]*//"
}

# Replace the first unfenced `- key:` line in place, or append when there is none.
# $4 is the already-sed-escaped value; $3 is the raw value used for the append.
#
# Line-addressed: exactly the one line the reader reads. This also narrows the edit from
# "every column-0 match" to "the first unfenced one" -- deliberate, because that is the line
# extract_field_value returns, and a capsule carrying two real copies of one field is a
# defect the validator should surface rather than one this tool should quietly keep in sync.
write_unfenced_field() {
  local file_path="$1"
  local key="$2"
  local normalized="$3"
  local escaped="$4"
  local target_line="$5"

  if [[ -n "$target_line" ]]; then
    sed -i.bak "${target_line}s|^- ${key}:.*|- ${key}: ${escaped}|" "$file_path"
    rm -f "${file_path}.bak"
    return 0
  fi

  # Refuse rather than append into an unterminated fence -- the shared guard, so the row
  # writers get the same answer this one does (r01 finding 5, r02 finding 1). A write that
  # guesses corrupts, and an unterminated fence is a defect in the document that the author
  # has to close, not one this tool can place a field around.
  require_appendable "$file_path" "$key"
  printf -- "- %s: %s\n" "$key" "$normalized" >> "$file_path"
}
