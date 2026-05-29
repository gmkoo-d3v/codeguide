import os
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCAFFOLD = ROOT / "scripts" / "init_docs_scaffold.sh"

FORBIDDEN_PATTERNS = [
    re.compile(pattern, re.IGNORECASE)
    for pattern in [
        r"\bantigravity\b",
        r"\bagy\b",
        r"\bgemini\b",
        r"\bclaude\b",
        r"\bcodex\b",
        r"\bopenai\b",
        r"\bgpt\b",
        r"\b[a-z0-9._-]*flash-[a-z0-9._-]*\b",
        r"\bgpt-[a-z0-9._-]+\b",
        r"\bclaude-opus-[a-z0-9._-]+\b",
        r"\bgemini-3[a-z0-9._-]*\b",
    ]
]


def _generated_docs_files(docs_root: Path) -> list[Path]:
    return sorted(path for path in docs_root.rglob("*") if path.is_file())


def test_scaffold_generated_docs_are_vendor_neutral(tmp_path: Path) -> None:
    project_root = tmp_path / "sample-project"
    project_root.mkdir()

    env = os.environ.copy()
    env.pop("CODEGUIDE" + "_ROOT", None)
    subprocess.run(
        [str(SCAFFOLD), str(project_root)],
        cwd=ROOT,
        env=env,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    docs_root = project_root / "docs"
    leaks: list[str] = []
    for path in _generated_docs_files(docs_root):
        text = path.read_text(encoding="utf-8")
        for lineno, line in enumerate(text.splitlines(), start=1):
            for pattern in FORBIDDEN_PATTERNS:
                if pattern.search(line):
                    rel = path.relative_to(project_root)
                    leaks.append(f"{rel}:{lineno}: {line}")
                    break

    assert leaks == []
