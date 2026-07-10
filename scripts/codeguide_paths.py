#!/usr/bin/env python3
"""Shared path policy for codeguide Python helpers."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path


def is_skill_package_root(candidate_root: Path) -> bool:
    """Return whether a directory looks like a reusable skill package."""
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


def _git_toplevel(start: Path) -> Path | None:
    """Return the git top-level for a path, or None when outside any repo."""
    try:
        result = subprocess.run(
            ["git", "-C", str(start), "rev-parse", "--show-toplevel"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (FileNotFoundError, subprocess.SubprocessError):
        return None
    top = result.stdout.strip()
    return Path(top).resolve(strict=False) if top else None


def resolve_project_root(input_root: Path) -> Path:
    """Resolve to the git root when possible, otherwise to the selected root."""
    root = input_root.expanduser().resolve(strict=False)
    if not root.exists():
        return root

    git_root = _git_toplevel(root)
    resolved_root = git_root if git_root is not None else root

    parent_root = resolved_root.parent
    if is_skill_package_root(resolved_root) and not (resolved_root / "docs").is_dir() and (parent_root / "docs").is_dir():
        return parent_root.resolve(strict=False)
    return resolved_root


def source_root_for(input_root: Path) -> Path | None:
    """Resolve the git repository that owns the project's SOURCE code.

    The docs system-of-record root can differ from the source repo: in the
    reusable-skills layout the docs root sits one level ABOVE the skill's own
    repo and may itself be a docs-only local repo, so git operations (branch
    inference, diff-based change sets) must not target the docs root.
    CODEGUIDE_SOURCE_ROOT overrides all detection for ambiguous layouts.
    Returns None when no source repository is reachable or detection is
    ambiguous (multiple skill-package child repos).
    """
    override = os.environ.get("CODEGUIDE_SOURCE_ROOT")
    if override:
        override_path = Path(override).expanduser().resolve(strict=False)
        return override_path if override_path.is_dir() else None

    root = input_root.expanduser().resolve(strict=False)
    git_root = _git_toplevel(root)
    if git_root is not None and is_skill_package_root(git_root):
        return git_root

    project_root = resolve_project_root(input_root)
    candidates: list[Path] = []
    try:
        children = sorted(path for path in project_root.iterdir() if path.is_dir())
    except OSError:
        children = []
    for child in children:
        if not (child / ".git").exists():
            continue
        if is_skill_package_root(child):
            candidates.append(child)
    if len(candidates) == 1:
        return candidates[0]
    if len(candidates) > 1:
        return None

    return _git_toplevel(project_root)


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
