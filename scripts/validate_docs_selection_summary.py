import re
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[2])
import shadow_doc_parse  # shared fence rule

shadow_dir = Path(sys.argv[1])
MAX_LEN = 250
# A floor, not proof of usefulness: it only rules out degenerate values that cannot
# discriminate anything. No check can prove a sentence actually distinguishes a unit.
MIN_LEN = 12

unit_re = re.compile(r"^-\s+([A-Za-z0-9._-]+)\s*:\s*$")
child_re = re.compile(r"^\s+-\s*([a-z_]+)\s*:\s*(.*?)\s*$")
summary_re = re.compile(r"^\s*-\s*unit_summary\s*:\s*(\S.*?)\s*$")


def content_lines(path):
    try:
        raw = shadow_doc_parse.read_lines(path)
    except OSError:
        return []
    return list(shadow_doc_parse.content_lines(raw))


issues = []
for index in sorted(shadow_dir.glob("*/_index.md")):
    unit, fields, last_field = None, {}, None

    def flush(unit, fields):
        if unit is None:
            return
        overview = fields.get("overview_doc", "")
        selection = fields.get("selection_summary", "")
        if not overview:
            # The navigation-link check only follows references that EXIST, so a row
            # with no overview_doc at all is reported by nothing else.
            issues.append((str(index), unit, "no_overview", ""))
            return
        if not selection:
            issues.append((str(index), unit, "missing", ""))
            return
        if fields.get("selection_summary__multiline"):
            issues.append((str(index), unit, "multiline", ""))
            return
        if len(selection) < MIN_LEN:
            issues.append((str(index), unit, "too_short", str(len(selection))))
            return
        if len(selection) > MAX_LEN:
            issues.append((str(index), unit, "too_long", str(len(selection))))
            return
        # overview_doc is written relative to the BUCKET directory ("unit/overview.md").
        # The navigation-link check accepts EITHER base but tries the shadow root
        # first; this check tries the bucket dir first because that is the base the
        # template in the contract uses, so the two can only disagree for a name
        # that resolves under both -- in which case nav-link reports nothing and this
        # check reads the bucket-local file, which is the one the row meant.
        target = index.parent / overview
        if not target.is_file():
            target = shadow_dir / overview
        if not target.is_file():
            return  # a dangling overview_doc belongs to the nav-link check
        summary = ""
        for line in content_lines(target):
            match = summary_re.match(line)
            if match:
                summary = match.group(1).strip()
                break
        if not summary:
            issues.append((str(index), unit, "no_summary", overview))
        elif not summary.startswith(selection):
            issues.append((str(index), unit, "not_prefix", overview))

    in_units = False
    for line in content_lines(index):
        # Bound the scan to the "## Units" section. Without it, any column-0 bullet
        # with an empty value parses as a unit row -- including `- bucket:` and
        # `- last_updated:` straight from the Bucket Registry Template, which then
        # report as rows with no overview_doc. Same section gate as
        # bucket_index_has_units() further up this file.
        if line.startswith("## "):
            flush(unit, fields)
            unit, fields, last_field = None, {}, None
            in_units = line.strip() == "## Units"
            continue
        if not in_units:
            continue
        unit_match = unit_re.match(line)
        if unit_match:
            flush(unit, fields)
            unit, fields, last_field = unit_match.group(1), {}, None
            continue
        child = child_re.match(line)
        if child and unit is not None:
            fields[child.group(1)] = child.group(2).strip()
            last_field = child.group(1)
            continue
        # An indented non-bullet line continues the previous field. The contract says
        # one line, so record it rather than silently reading only the first line.
        if unit is not None and last_field and line.startswith(" ") and line.strip():
            fields[last_field + "__multiline"] = "yes"
            continue
    flush(unit, fields)

for item in issues:
    print("\t".join(item))
