#!/usr/bin/env python3
"""User-owned external review executor for CodeGuide current-task jobs."""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

from ai_model_registry import RegistryError, load_registry
from codeguide_paths import docs_root_for, resolve_project_root
from external_review_runner import execute_debate


def discover_task_ids(project_root: Path, task_id: str | None) -> list[str]:
    if task_id:
        debate_file = docs_root_for(project_root) / "orchestration" / task_id / "current-task" / "debate.json"
        return [task_id] if debate_file.is_file() else []
    orchestration_root = docs_root_for(project_root) / "orchestration"
    if not orchestration_root.is_dir():
        return []
    task_ids: list[str] = []
    for debate_file in sorted(orchestration_root.glob("*/current-task/debate.json")):
        task_ids.append(debate_file.parent.parent.name)
    return task_ids


def run_available_jobs(args: argparse.Namespace) -> int:
    if not args.egress_approved:
        print(
            "[ERROR] --egress-approved is required because this user-owned executor sends review content to external CLI services.",
            file=sys.stderr,
        )
        return 64
    project_root = resolve_project_root(args.project_root)
    registry = load_registry(args.registry)
    task_ids = discover_task_ids(project_root, args.task_id)
    if not task_ids:
        if args.task_id:
            print(f"[ERROR] current-task debate job not found for task_id={args.task_id}", file=sys.stderr)
            return 64
        print("[INFO] no current-task debate jobs found")
        return 0

    failures = 0
    for task_id in task_ids:
        status = execute_debate(
            project_root=project_root,
            registry=registry,
            task_id=task_id,
            force=args.force,
            dry_run=False,
            runner_filter=args.runner,
            executor_kind="user_owned_executor",
        )
        if status != 0:
            failures += 1
    return 1 if failures else 0


def main(argv: list[str] | None = None) -> int:
    default_registry = Path(__file__).resolve().parent.parent / "config" / "ai_model_registry.json"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path("."))
    parser.add_argument("--registry", type=Path, default=Path(os.environ.get("CODEGUIDE_MODEL_REGISTRY", default_registry)))
    parser.add_argument("--runner", choices=["agy", "claude", "codex", "all"], default="all")
    parser.add_argument("--task-id")
    parser.add_argument("--egress-approved", action="store_true")
    parser.add_argument("--force", action="store_true")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--run-once", action="store_true")
    mode.add_argument("--watch", action="store_true")
    parser.add_argument("--interval", type=float, default=15.0)
    args = parser.parse_args(argv)

    try:
        if args.run_once:
            return run_available_jobs(args)
        while True:
            status = run_available_jobs(args)
            if status != 0:
                return status
            time.sleep(args.interval)
    except KeyboardInterrupt:
        return 130
    except (RegistryError, ValueError, OSError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
