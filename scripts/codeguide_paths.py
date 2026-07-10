#!/usr/bin/env python3
"""Shared path policy for codeguide Python helpers."""

from __future__ import annotations

import os
import subprocess
import sys
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


def _warn(message: str) -> None:
    print(message, file=sys.stderr)


def _normalize_source_dir(raw_dir: Path, label: str) -> Path | None:
    """Normalize an EXPLICITLY declared source location to its git toplevel.

    git prints toplevel-relative diff paths, so returning a subdirectory here
    would silently empty every downstream change set — and an explicit
    declaration (env override or marker file) that is not a git repository is
    a configuration error, so it fails closed instead of degrading.
    """
    dir_abs = raw_dir.expanduser().resolve(strict=False)
    if not dir_abs.is_dir():
        _warn(f"[WARN] {label} is not a readable directory: {raw_dir}")
        return None
    git_root = _git_toplevel(dir_abs)
    if git_root is not None:
        return git_root
    _warn(f"[WARN] {label} does not resolve inside a git repository; fix the declaration or unset it: {raw_dir}")
    return None


def _skill_package_child_repos(project_root: Path) -> list[Path]:
    try:
        children = sorted(path for path in project_root.iterdir() if path.is_dir() and not path.name.startswith("."))
    except OSError:
        return []
    return [child for child in children if (child / ".git").exists() and is_skill_package_root(child)]


def source_root_for(input_root: Path) -> Path | None:
    """Resolve the git repository that owns the project's SOURCE code.

    The docs system-of-record root can differ from the source repo: in the
    reusable-skills layout the docs root sits one level ABOVE the skill's own
    repo and may itself be a docs-only local repo, so git operations (branch
    inference, diff-based change sets) must not target the docs root.

    Precedence, most explicit first: CODEGUIDE_SOURCE_ROOT (normalized to its
    git toplevel); the `.codeguide-source-root` marker file at the docs root
    (the explicit contract for docs-only parent repos); the input path's own
    repo when it is a skill package; the project root's enclosing repo (an
    ordinary project — a nested skill-package child never hijacks it); a
    unique skill-package child repo only when the project root is not inside
    any repo. Returns None (with a stderr warning) on failure or ambiguity.
    """
    override = os.environ.get("CODEGUIDE_SOURCE_ROOT")
    if override:
        return _normalize_source_dir(Path(override), "CODEGUIDE_SOURCE_ROOT")

    root = input_root.expanduser().resolve(strict=False)
    project_root = resolve_project_root(input_root)

    marker_file = project_root / ".codeguide-source-root"
    if marker_file.is_file():
        try:
            marker_lines = marker_file.read_text(encoding="utf-8").splitlines()
        except OSError:
            marker_lines = []
        marker_target = marker_lines[0].strip() if marker_lines else ""
        if not marker_target:
            _warn(f"[WARN] .codeguide-source-root is empty: {marker_file}")
            return None
        target = Path(marker_target)
        if not target.is_absolute():
            target = project_root / target
        return _normalize_source_dir(target, ".codeguide-source-root")

    git_root = _git_toplevel(root)
    if git_root is not None and is_skill_package_root(git_root):
        return git_root

    project_git_root = _git_toplevel(project_root)
    if project_git_root is not None:
        if _skill_package_child_repos(project_root):
            _warn(
                f"[INFO] Source root is the enclosing repo of {project_root}; a nested skill-package repo was not "
                "selected. For a docs-only root, declare .codeguide-source-root or set CODEGUIDE_SOURCE_ROOT."
            )
        return project_git_root

    candidates = _skill_package_child_repos(project_root)
    if len(candidates) == 1:
        return candidates[0]
    if len(candidates) > 1:
        _warn(
            f"[WARN] Multiple skill-package source repositories under {project_root}; set CODEGUIDE_SOURCE_ROOT "
            "or declare .codeguide-source-root to disambiguate."
        )
        return None

    return None


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
