# codeguide_doc_lines.sh -- the ONE shell adapter over the shared document reader.
# Sourced (never executed) by every shell tool that TOUCHES a docs capsule: the writers
# (doc_garden.sh, run_external_plan_reviews.sh) that edit fields by line number, and the
# validator (validate_docs.sh) that sources this BEFORE its rule modules so the envelope
# reader below is one implementation shared by writer and reader. Requires
# CODEGUIDE_DOC_LINES_SCRIPT_DIR, or falls back to this file's own directory, to locate
# shadow_doc_parse.py.
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
# One asymmetry is load-bearing and stays: the WRITE side of this adapter is LOUD
# (require_unfenced_lines) where the validator's read side degrades to the original
# document on purpose. A misreported read costs a wrong warning, while a write that
# guessed wrong would corrupt a capsule -- so the two keep their different failure modes.
#
# doc_lines_envelope adds the metadata-envelope question to the shared reader in pure
# shell: the fence-stripped lines before the first unfenced `##` heading
# (task-state-contract.md, "metadata envelope"). It is the boundary every envelope-aware
# rule and every envelope-aware writer answer by, and it never spawns python -- a
# validator that already paid for a fence-stripped cache copy hands that copy in and
# reads envelopes for free, and a writer holding only the raw file gets the same answer
# from the same walk.

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

# The metadata envelope: the fence-stripped lines of a document BEFORE the first
# unfenced `##` heading. Everything at or below that heading is narrative by contract
# and is never schema (task-state-contract.md), so this is the boundary every
# envelope-aware read -- close-field extraction, unknown-key scan, placeholder check --
# and every envelope-aware write answers by, and it is exactly ONE implementation,
# shared by the validator and the writers that source this file.
#
# Pure shell on purpose, and it never spawns python: the validator pre-strips the corpus
# once (validate_docs.sh) and hands this function the fence-stripped cache copy, so the
# walk below is a no-op there and a cached envelope read costs nothing; a writer holding
# only the raw file gets the same boundary from the same walk instead of from a private
# fence rule.
#
# The fence walk implements the ONE fence grammar (shadow_doc_parse, so the stripped copy
# and a raw document cannot disagree): a line whose leading-whitespace-stripped form
# starts with three backticks or three tildes opens a block, a block closes only on a
# marker of the SAME character at least as long as the opener, and an unterminated block
# runs to end of document. A fenced `##` is content of the block, never a boundary; fence
# markers and fenced content are excluded from the output.
#
# Prints the envelope lines verbatim (blank lines included, indentation preserved), one
# per line; prints nothing when the file is unreadable or the envelope is empty.
doc_lines_envelope() {
  local file_path="$1"
  local line
  local stripped
  local run
  local marker_char
  local marker_len
  local open_char=""
  local open_len=0

  [[ -f "$file_path" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    stripped="${line#"${line%%[![:space:]]*}"}"

    if [[ -z "$open_char" ]]; then
      if [[ "$stripped" == \`\`\`* || "$stripped" == \~\~\~* ]]; then
        marker_char="${stripped:0:1}"
        if [[ "$marker_char" == "~" ]]; then
          run="${stripped%%[!~]*}"
        else
          run="${stripped%%[!\`]*}"
        fi
        open_char="$marker_char"
        open_len="${#run}"
        continue
      fi
      # First unfenced heading of level 2+ ends the envelope.
      if [[ "$stripped" == "##"* ]]; then
        return 0
      fi
      printf '%s\n' "$line"
      continue
    fi

    # Inside a fenced block: only a same-character marker at least as long as the opener
    # closes it; everything else -- `##`, other marker flavours, content -- stays inside.
    if [[ "$stripped" == \`\`\`* || "$stripped" == \~\~\~* ]]; then
      marker_char="${stripped:0:1}"
      if [[ "$marker_char" == "~" ]]; then
        run="${stripped%%[!~]*}"
      else
        run="${stripped%%[!\`]*}"
      fi
      if [[ "$marker_char" == "$open_char" && "${#run}" -ge "$open_len" ]]; then
        open_char=""
        open_len=0
      fi
    fi
  done < "$file_path"
  return 0
}

# Envelope-bounded close-field BLOCK reader, pure shell, for the WRITE side and for
# shared stored-field projection (task_index_projection_summary below). It is the
# writer's counterpart to extract_field_block (validate_docs.d/10-parse.sh): same
# envelope (doc_lines_envelope), same first-occurrence-wins anchor, same termination
# rules, so a row summary derived here and a close-field read there answer the same
# question. A second block walker exists only because the validator module is not
# sourced by the writers; the boundary they share is the one implementation that
# matters, and both walks are pinned by bats (task_envelope.bats for the validator
# side, task_index_projection.bats for this one).
#
# Accepts an inline scalar (`- outcome: done`) and contiguous nested bullets as
# filled; returns empty for fence-only/bare-dash/checkbox/whitespace/HTML-comment/
# heading-only content; terminates at the next column-0 key (same key included),
# heading, EOF, blank line, or unindented prose; first duplicate wins. A blank line
# terminates even inside a run of nested bullets.
doc_lines_block_value() {
  local file_path="$1"
  local key="$2"
  local line
  local stripped
  local remainder
  local content=""
  local found=0
  local in_block=0
  local all_empty=1
  local is_blank

  [[ -f "$file_path" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "${line//[[:space:]]/}" ]]; then
      is_blank=1
    else
      is_blank=0
    fi

    if (( ! in_block )); then
      # Target key line: first column-0 occurrence wins.
      if [[ "$line" == "- ${key}:"* ]]; then
        remainder="${line#- ${key}:}"
        remainder="${remainder#"${remainder%%[![:space:]]*}"}"
        if [[ -n "$remainder" ]]; then
          # Inline scalar: the whole value sits on the key line, trimmed the same
          # way extract_field_value trims.
          printf "%s" "$remainder" | sed 's/[[:space:]]*$//'
          return 0
        fi
        found=1
        in_block=1
        content=""
        all_empty=1
        continue
      fi
      # Any other column-0 bullet is the next key once the target was found.
      if [[ "$line" == "- "* ]]; then
        (( found )) && break
        continue
      fi
      # The envelope ends before any heading by construction; a heading seen here
      # still stops the walk defensively.
      stripped="${line#"${line%%[![:space:]]*}"}"
      if [[ "$stripped" == "##"* ]]; then
        break
      fi
      if (( is_blank )); then
        (( found )) && break
        continue
      fi
      # Unindented prose: terminates once the target was found.
      (( found )) && break
      continue
    fi

    # Inside the block: a blank line or any column-0 line terminates it.
    if (( is_blank )); then
      break
    fi
    if [[ "$line" != [[:space:]]* ]]; then
      break
    fi
    # Indented content -- nested bullets (including `  - key:`), indented prose.
    content+="$line"$'\n'
    stripped="${line#"${line%%[![:space:]]*}"}"
    stripped="${stripped%"${stripped##*[![:space:]]}"}"
    case "$stripped" in
      "-"|"- [ ]"|"<!--"*) ;;
      *) all_empty=0 ;;
    esac
  done < <(doc_lines_envelope "$file_path")

  if (( ! found || ! in_block || all_empty )); then
    return 0
  fi
  printf '%s' "$content" | sed 's/[[:space:]]*$//'
}

# Canonical single-line task-index ROW summary (the plan,
# r07): collapse meaningful lines -> whitespace normalization -> pipe escaping. Each
# meaningful line contributes its bullet-marker-stripped content and lines are joined
# with '; ' -- the bullet syntax is the join point, so no information is lost and the
# first-line-only shortcut is forbidden. Blank lines and bare dashes are dropped. Pipes
# are escaped as `\|`, the same escape the task-index row writer has always used, so a
# row built from this value and the value itself are byte-identical.
task_index_summary_canonical() {
  local value="$1"
  local line
  local stripped
  local joined=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Drop trailing whitespace; a blank line is not meaningful content.
    stripped="${line%"${line##*[![:space:]]}"}"
    [[ -n "$stripped" ]] || continue
    # Strip leading whitespace, then the bullet marker (`- `) if present. A bare
    # dash (`-` with nothing after it) is a marker with no content and is dropped.
    stripped="${stripped#"${stripped%%[![:space:]]*}"}"
    if [[ "$stripped" == "- "* ]]; then
      stripped="${stripped#- }"
    elif [[ "$stripped" == "-" ]]; then
      stripped=""
    fi
    [[ -n "$stripped" ]] || continue
    if [[ -n "$joined" ]]; then
      joined+="; "
    fi
    joined+="$stripped"
  done <<< "$value"

  printf "%s" "$joined" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ +//; s/ +$//' | sed 's/|/\\|/g'
}

# The task-index ROW summary derives from the TASK FILE's stored fields, never from
# CLI-passed text. The map is
# fixed: planned/in_progress/blocked -> title, done -> outcome, superseded/cancelled ->
# disposition. Reusing is_active_task_status (which includes done) for this is FORBIDDEN:
# done projects to outcome, not title. Every read is envelope-bounded (doc_lines_block_value),
# so a close field written below the first unfenced `##` heading is narrative and never
# becomes a row summary. This is the ONE implementation both the writer (doc_garden.sh
# update_task_index / --rebuild-task-index) and the validator (check_task_index_projection
# in validate_docs.d/30-rules-task.sh) call, so a row written by the garden and a row
# checked by the validator cannot disagree.
task_index_projection_summary() {
  local task_file="$1"
  local status="$2"
  local value=""

  case "$status" in
    done)
      value="$(doc_lines_block_value "$task_file" "outcome")"
      ;;
    superseded|cancelled)
      value="$(doc_lines_block_value "$task_file" "disposition")"
      ;;
    *)
      value="$(doc_lines_block_value "$task_file" "title")"
      ;;
  esac

  task_index_summary_canonical "$value"
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
