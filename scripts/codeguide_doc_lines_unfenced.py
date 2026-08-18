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
