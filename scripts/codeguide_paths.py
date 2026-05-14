#!/usr/bin/env python3
"""Shared path policy for codeguide Python helpers."""

from __future__ import annotations

import subprocess
from pathlib import Path


def is_skill_package_root(candidate_root: Path) -> bool:
    """Return whether a directory looks like a reusable Codex skill package."""
    skill_file = candidate_root / "SKILL.md"
    if not skill_file.is_file():
        return False
    try:
        has_name = any(line.startswith("name:") and line.split(":", 1)[1].strip() for line in skill_file.read_text().splitlines())
    except OSError:
        return False
    if not has_name:
        return False
    return any((candidate_root / child).is_dir() for child in ("scripts", "references", "tests"))


def resolve_project_root(input_root: Path) -> Path:
    """Resolve to the git root when possible, otherwise to the selected root."""
    root = input_root.expanduser().resolve(strict=False)
    if not root.exists():
        return root

    try:
        result = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--show-toplevel"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (FileNotFoundError, subprocess.SubprocessError):
        resolved_root = root
    else:
        git_root = result.stdout.strip()
        resolved_root = Path(git_root).resolve(strict=False) if git_root else root

    parent_root = resolved_root.parent
    if is_skill_package_root(resolved_root) and not (resolved_root / "docs").is_dir() and (parent_root / "docs").is_dir():
        return parent_root.resolve(strict=False)
    return resolved_root


def docs_root_for(project_root: Path) -> Path:
    """Return the canonical docs root for a project."""
    return resolve_project_root(project_root) / "docs"


def orchestration_root_for(project_root: Path) -> Path:
    """Return the canonical orchestration docs root for a project."""
    return docs_root_for(project_root) / "orchestration"


def orchestration_templates_dir_for(project_root: Path) -> Path:
    """Return the canonical orchestration template directory."""
    return orchestration_root_for(project_root) / "_templates"


def orchestration_task_dir_for(project_root: Path, task_id: str) -> Path:
    """Return the canonical orchestration capsule directory for a task."""
    return orchestration_root_for(project_root) / task_id


def orchestration_file_for(project_root: Path, task_id: str) -> Path:
    """Return the canonical orchestration state document for a task."""
    return orchestration_task_dir_for(project_root, task_id) / "ORCH.md"


def external_cli_dir_for(project_root: Path, task_id: str, plan_version: str, review_round: str) -> Path:
    """Return the canonical external CLI handoff directory for a review round."""
    return orchestration_task_dir_for(project_root, task_id) / "external-cli" / plan_version / review_round
