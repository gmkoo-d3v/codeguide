import sys
from pathlib import Path

sys.path.insert(0, sys.argv[3])
sys.dont_write_bytecode = True
import shadow_doc_parse

docs_dir = Path(sys.argv[1])
cache = Path(sys.argv[2])
for doc in docs_dir.rglob("*.md"):
    try:
        lines = shadow_doc_parse.read_lines(doc)
    except OSError:
        continue
    # Key on the path AS WALKED, never doc.resolve(): the shell side looks the file
    # up by the path it holds, which is built from DOCS_DIR. On macOS a test workspace
    # under /var/folders is a symlink to /private/var/folders, so a resolved key misses
    # every single lookup and every field read silently falls back to a python spawn --
    # correct output, 100-115s instead of 29s, which is the exact regression this cache
    # exists to prevent.
    dest = cache / str(doc).lstrip("/")
    # Stage then rename: a partial write must never become a served cache entry. The
    # shell side additionally refuses a zero-byte entry, but the two together are what
    # make "the cache is either absent or complete" true rather than merely likely.
    staged = dest.with_name(dest.name + ".part")
    try:
        dest.parent.mkdir(parents=True, exist_ok=True)
        staged.write_text("\n".join(shadow_doc_parse.content_lines(lines)) + "\n", encoding="utf-8")
        staged.replace(dest)
    except OSError:
        continue
