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
    excluded = {
        docs_root / "orchestration" / "_templates" / "ORCH.md",
    }
    return sorted(path for path in docs_root.rglob("*") if path.is_file() and path not in excluded)


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


def test_scaffold_orch_template_includes_external_review_manual_fields(tmp_path: Path) -> None:
    project_root = tmp_path / "sample-project"
    project_root.mkdir()

    subprocess.run(
        [str(SCAFFOLD), str(project_root)],
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    orch_template = project_root / "docs" / "orchestration" / "_templates" / "ORCH.md"
    text = orch_template.read_text(encoding="utf-8")

    for field in [
        "external_review_status",
        "external_review_required_for",
        "required_review_routes",
        "external_review_round",
        "external_review_result_ref",
        "external_review_waiver_ref",
        "external_review_waiver_reason",
    ]:
        assert f"- {field}:" in text

    for field in [
        "primary_author_tool",
        "review_mode",
        "external_review_status",
        "external_review_required_for",
        "delegation_status",
        "risk_preflight_status",
        "approval_required",
    ]:
        line = next(line for line in text.splitlines() if line.startswith(f"- {field}:"))
        assert "|" not in line
