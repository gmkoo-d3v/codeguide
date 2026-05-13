#!/usr/bin/env python3
"""Shared path policy for codeguide Python helpers."""

from __future__ import annotations

import subprocess
from pathlib import Path


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
        return root

    git_root = result.stdout.strip()
    return Path(git_root).resolve(strict=False) if git_root else root


def docs_root_for(project_root: Path) -> Path:
    """Return the canonical docs root for a project."""
    return resolve_project_root(project_root) / "docs"
