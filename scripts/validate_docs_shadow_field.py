import sys
from pathlib import Path

sys.path.insert(0, sys.argv[3])
import shadow_doc_parse

try:
    lines = shadow_doc_parse.read_lines(sys.argv[1])
except OSError:
    sys.exit(0)
value = shadow_doc_parse.field_value(lines, sys.argv[2])
if value:
    print(value)
