import re
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[2])
import shadow_doc_parse  # shared fence rule

shadow_dir = Path(sys.argv[1])
field_re = re.compile(r"^\s*-\s*secondary_tags\s*:")

for doc in sorted(shadow_dir.rglob("*.md")):
    parts = doc.relative_to(shadow_dir).parts
    if parts and parts[0] in ("_deprecated", "_obsolete"):
        continue
    try:
        lines = shadow_doc_parse.read_lines(doc)
    except OSError:
        continue
    for line in shadow_doc_parse.content_lines(lines):
        if field_re.match(line):
            print(doc)
            break
