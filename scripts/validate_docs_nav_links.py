import re
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[4])
import shadow_doc_parse  # one answer to "is this line inside a fence"

shadow_dir = Path(sys.argv[1])
project_root = Path(sys.argv[2])
docs_dir = Path(sys.argv[3])

path_fields = ("canonical_path", "overview_doc", "next_docs", "bucket_links", "global_doc")
fields_alt = "|".join(path_fields)
# A path field with an inline value on the same line.
inline_re = re.compile(r"^\s*-\s*(" + fields_alt + r")\s*:\s*(\S.*?)\s*$")
# A bare path-field header whose values are nested bullet lines beneath it.
header_re = re.compile(r"^(\s*)-\s*(" + fields_alt + r")\s*:\s*$")
bullet_re = re.compile(r"^(\s*)-\s+(.*?)\s*$")
# A doc token is a run of path characters ending in .md. The restricted class
# stops the greedy match at Markdown link punctuation, so [label](auth.md) and
# <auth.md> both yield the bare path auth.md rather than a garbled token.
token_re = re.compile(r"[A-Za-z0-9._/-]+\.md\b")


def resolves(ref_file: Path, token: str) -> bool:
    token = token.strip()
    if not token:
        return True
    candidate = Path(token)
    if candidate.is_absolute():
        try:
            return candidate.resolve(strict=False).is_file()
        except OSError:
            return False
    # Precise bases: docs/-prefixed refs (redirect shims) are project-root
    # relative; every other shadow ref resolves against the shadow root or the
    # directory of the referencing doc. This avoids a whole-project search that
    # would let an unrelated same-named file mask a genuinely dangling ref.
    if token.startswith("docs/"):
        bases = (project_root,)
    else:
        bases = (shadow_dir, ref_file.parent)
    for base in bases:
        try:
            if (base / candidate).resolve(strict=False).is_file():
                return True
        except OSError:
            continue
    return False


def scan_value(ref_file: Path, field: str, value: str, issues: list) -> None:
    for token in token_re.findall(value):
        if not resolves(ref_file, token):
            issues.append((str(ref_file), field, token))


issues = []
for md in sorted(shadow_dir.rglob("*.md")):
    rel_parts = md.relative_to(shadow_dir).parts
    if rel_parts and rel_parts[0] in ("_deprecated", "_obsolete"):
        continue
    try:
        lines = shadow_doc_parse.read_lines(md)
    except OSError:
        continue
    pending_field = None
    pending_indent = -1
    for kind, line in shadow_doc_parse.scan(lines):
        if kind == "boundary":
            pending_field = None
            continue
        inline = inline_re.match(line)
        if inline:
            pending_field = None
            scan_value(md, inline.group(1), inline.group(2), issues)
            continue
        header = header_re.match(line)
        if header:
            pending_field = header.group(2)
            pending_indent = len(header.group(1))
            continue
        if pending_field is not None:
            bullet = bullet_re.match(line)
            if bullet and len(bullet.group(1)) > pending_indent:
                scan_value(md, pending_field, bullet.group(2), issues)
                continue
            if line.strip():
                pending_field = None

seen = set()
for ref_file, field, token in issues:
    key = (ref_file, field, token)
    if key in seen:
        continue
    seen.add(key)
    print(f"{ref_file}\t{field}\t{token}")
