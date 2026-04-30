#!/usr/bin/env python3
"""Read-only evidence probe for shadow effect-map facts.

The probe verifies a narrow validator or approved fallback pattern against an
explicit source/trace artifact. It never writes shadow docs and never promotes
facts by itself.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import fnmatch
import io
import json
import re
import sys
import tokenize
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


PASS = 0
FAIL = 1
UNSUPPORTED = 2
USAGE_ERROR = 64


@dataclass(frozen=True)
class PrimarySpec:
    evidence_type: str
    kind: str
    parser_backed: bool
    promotion_limit: str
    language: str = ""
    allowed_paths: tuple[str, ...] = ()
    excluded_paths: tuple[str, ...] = ()


@dataclass(frozen=True)
class FallbackSpec:
    evidence_type: str
    language: str
    pattern: str | None = None
    required_params: tuple[str, ...] = ()
    allowed_paths: tuple[str, ...] = ()
    excluded_paths: tuple[str, ...] = ()
    promotion_limit: str = "medium"


PRIMARY_VALIDATORS: dict[str, PrimarySpec] = {
    "any.runtime.trace@v1": PrimarySpec("runtime_trace", "runtime_trace", False, "high"),
    "java.annotation.match@v1": PrimarySpec(
        "annotation",
        "source_probe",
        False,
        "medium",
        "java",
        ("src/main/java/**",),
        ("src/test/**", "build/**", "target/**", ".gradle/**"),
    ),
    "spring_boot.request_mapping@v1": PrimarySpec(
        "annotation",
        "source_probe",
        False,
        "medium",
        "java",
        ("src/main/java/**",),
        ("src/test/**", "build/**", "target/**", ".gradle/**"),
    ),
    "spring_boot.cache_evict.annotation@v1": PrimarySpec(
        "annotation",
        "source_probe",
        False,
        "medium",
        "java",
        ("src/main/java/**",),
        ("src/test/**", "build/**", "target/**", ".gradle/**"),
    ),
    "jpa.repository.save@v1": PrimarySpec(
        "code_call",
        "source_probe",
        False,
        "medium",
        "java",
        ("src/main/java/**",),
        ("src/test/**", "build/**", "target/**", ".gradle/**"),
    ),
    "py.ast.call_match@v1": PrimarySpec(
        "code_call",
        "ast",
        True,
        "high",
        "python",
        ("**/*.py",),
        ("tests/**", ".venv/**", "venv/**", "build/**", "dist/**"),
    ),
    "py.decorator.match@v1": PrimarySpec(
        "annotation",
        "ast",
        True,
        "high",
        "python",
        ("**/*.py",),
        ("tests/**", ".venv/**", "venv/**", "build/**", "dist/**"),
    ),
}


FALLBACK_PATTERNS: dict[str, FallbackSpec] = {
    "java.regex.method_call_named@v1": FallbackSpec(
        evidence_type="code_call",
        language="java",
        pattern=r"\b{{receiver}}\s*\.\s*{{method}}\s*\(",
        required_params=("receiver", "method"),
        allowed_paths=("src/main/java/**",),
        excluded_paths=("src/test/**", "build/**", "target/**", ".gradle/**"),
    ),
    "java.regex.repository_save_call@v1": FallbackSpec(
        evidence_type="code_call",
        language="java",
        pattern=r"\b[A-Za-z_][A-Za-z0-9_]*Repository\s*\.\s*save(?:AndFlush)?\s*\(",
        allowed_paths=("src/main/java/**",),
        excluded_paths=("src/test/**", "build/**", "target/**", ".gradle/**"),
    ),
    "java.regex.annotation_named@v1": FallbackSpec(
        evidence_type="annotation",
        language="java",
        pattern=r"@{{annotation}}\b",
        required_params=("annotation",),
        allowed_paths=("src/main/java/**",),
        excluded_paths=("src/test/**", "build/**", "target/**"),
    ),
    "spring_boot.regex.request_mapping@v1": FallbackSpec(
        evidence_type="annotation",
        language="java",
        pattern=r"@(?:GetMapping|PostMapping|PutMapping|PatchMapping|DeleteMapping|RequestMapping)\b",
        allowed_paths=("src/main/java/**",),
        excluded_paths=("src/test/**", "build/**", "target/**"),
    ),
    "js.regex.call_named@v1": FallbackSpec(
        evidence_type="code_call",
        language="javascript",
        pattern=r"\b{{callee}}\s*\(",
        required_params=("callee",),
        allowed_paths=("src/**", "app/**", "lib/**"),
        excluded_paths=("node_modules/**", "dist/**", "build/**", "**/*.test.*", "**/*.spec.*"),
    ),
    "ts.regex.decorator_named@v1": FallbackSpec(
        evidence_type="annotation",
        language="typescript",
        pattern=r"@{{decorator}}\b",
        required_params=("decorator",),
        allowed_paths=("src/**", "app/**", "lib/**"),
        excluded_paths=("node_modules/**", "dist/**", "build/**", "**/*.test.*", "**/*.spec.*"),
    ),
    "py.regex.call_named@v1": FallbackSpec(
        evidence_type="code_call",
        language="python",
        pattern=r"\b{{callee}}\s*\(",
        required_params=("callee",),
        allowed_paths=("**/*.py",),
        excluded_paths=("tests/**", ".venv/**", "venv/**", "build/**", "dist/**"),
    ),
    "py.regex.decorator_named@v1": FallbackSpec(
        evidence_type="annotation",
        language="python",
        pattern=r"@{{decorator}}\b",
        required_params=("decorator",),
        allowed_paths=("**/*.py",),
        excluded_paths=("tests/**", ".venv/**", "venv/**", "build/**", "dist/**"),
    ),
}


class ProbeError(Exception):
    pass


def emit(payload: dict[str, object]) -> None:
    print(json.dumps(payload, sort_keys=True, separators=(",", ":")))


def emit_error(message: str, args: argparse.Namespace | None = None) -> int:
    payload: dict[str, object] = {"status": "error", "error": message}
    if args is not None:
        if args.validator_id:
            payload["validator_id"] = args.validator_id
        if args.fallback_pattern_id:
            payload["fallback_pattern_id"] = args.fallback_pattern_id
    emit(payload)
    return USAGE_ERROR


def normalize_rel_path(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def resolve_inside(root: Path, raw_path: str | None, label: str) -> Path:
    if not raw_path:
        raise ProbeError(f"{label} is required")

    candidate = Path(raw_path)
    if ".." in candidate.parts:
        raise ProbeError(f"{label} must not contain traversal segments")
    if not candidate.is_absolute():
        candidate = root / candidate

    try:
        resolved = candidate.resolve(strict=True)
    except FileNotFoundError as exc:
        raise ProbeError(f"{label} does not exist: {raw_path}") from exc

    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise ProbeError(f"{label} must stay under project root: {raw_path}") from exc

    if not resolved.is_file():
        raise ProbeError(f"{label} must be a file: {raw_path}")
    return resolved


def path_matches(path: str, pattern: str) -> bool:
    if fnmatch.fnmatch(path, pattern):
        return True
    if pattern.startswith("**/") and fnmatch.fnmatch(path, pattern[3:]):
        return True
    return False


def enforce_path_scope(rel_path: str, spec: FallbackSpec) -> None:
    if spec.allowed_paths and not any(path_matches(rel_path, pattern) for pattern in spec.allowed_paths):
        raise ProbeError(f"source file is outside allowed_paths for fallback pattern: {rel_path}")
    if any(path_matches(rel_path, pattern) for pattern in spec.excluded_paths):
        raise ProbeError(f"source file is excluded for fallback pattern: {rel_path}")


def enforce_primary_path_scope(rel_path: str, spec: PrimarySpec) -> None:
    if spec.allowed_paths and not any(path_matches(rel_path, pattern) for pattern in spec.allowed_paths):
        raise ProbeError(f"source file is outside allowed_paths for primary validator: {rel_path}")
    if any(path_matches(rel_path, pattern) for pattern in spec.excluded_paths):
        raise ProbeError(f"source file is excluded for primary validator: {rel_path}")


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file_handle:
        for chunk in iter(lambda: file_handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return f"sha256:{digest.hexdigest()}"


def line_for_offset(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def mask_c_like_code(text: str) -> str:
    chars = list(text)
    i = 0
    state = "code"
    quote = ""

    while i < len(chars):
        c = chars[i]
        nxt = chars[i + 1] if i + 1 < len(chars) else ""

        if state == "code":
            if c == "/" and nxt == "/":
                chars[i] = chars[i + 1] = " "
                i += 2
                state = "line_comment"
                continue
            if c == "/" and nxt == "*":
                chars[i] = chars[i + 1] = " "
                i += 2
                state = "block_comment"
                continue
            if c in ("'", '"', "`"):
                quote = c
                chars[i] = " "
                i += 1
                state = "string"
                continue
            i += 1
            continue

        if state == "line_comment":
            if c == "\n":
                state = "code"
            else:
                chars[i] = " "
            i += 1
            continue

        if state == "block_comment":
            if c == "*" and nxt == "/":
                chars[i] = chars[i + 1] = " "
                i += 2
                state = "code"
                continue
            if c != "\n":
                chars[i] = " "
            i += 1
            continue

        if state == "string":
            if c == "\\":
                chars[i] = " "
                if i + 1 < len(chars) and chars[i + 1] != "\n":
                    chars[i + 1] = " "
                i += 2
                continue
            if c == quote:
                chars[i] = " "
                i += 1
                state = "code"
                continue
            if c != "\n":
                chars[i] = " "
            i += 1

    return "".join(chars)


def mask_python_code(text: str) -> str:
    lines = [list(line) for line in text.splitlines(keepends=True)]
    try:
        tokens = tokenize.generate_tokens(io.StringIO(text).readline)
        for token in tokens:
            if token.type not in (tokenize.COMMENT, tokenize.STRING):
                continue
            (start_row, start_col), (end_row, end_col) = token.start, token.end
            for row in range(start_row, end_row + 1):
                line = lines[row - 1]
                start = start_col if row == start_row else 0
                end = end_col if row == end_row else len(line)
                for col in range(start, min(end, len(line))):
                    if line[col] != "\n":
                        line[col] = " "
    except tokenize.TokenError:
        return text
    return "".join("".join(line) for line in lines)


def mask_for_language(text: str, language: str) -> str:
    if language == "python":
        return mask_python_code(text)
    if language in {"java", "javascript", "typescript"}:
        return mask_c_like_code(text)
    return text


def ast_call_name(node: ast.AST) -> str | None:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        base = ast_call_name(node.value)
        return f"{base}.{node.attr}" if base else node.attr
    return None


def name_matches(actual: str | None, expected: str) -> bool:
    if actual is None:
        return False
    return actual == expected or (("." not in expected) and actual.split(".")[-1] == expected)


def param(args: argparse.Namespace, name: str) -> str | None:
    value = getattr(args, name, None)
    if value:
        return value
    return getattr(args, "symbol", None)


def compile_pattern(template: str, args: argparse.Namespace, required: Iterable[str]) -> re.Pattern[str]:
    pattern = template
    for item in required:
        value = param(args, item)
        if not value:
            raise ProbeError(f"--{item.replace('_', '-')} is required for this fallback pattern")
        pattern = pattern.replace("{{" + item + "}}", re.escape(value))
    return re.compile(pattern, re.MULTILINE)


def match_regex_source(args: argparse.Namespace, root: Path, pattern_id: str, spec: FallbackSpec) -> tuple[bool, dict[str, object]]:
    source = resolve_inside(root, args.source_file, "source file")
    rel_path = normalize_rel_path(source, root)
    enforce_path_scope(rel_path, spec)

    text = read_text(source)
    masked = mask_for_language(text, spec.language)
    regex = compile_pattern(spec.pattern or "", args, spec.required_params)
    match = regex.search(masked)
    payload = {
        "status": "pass" if match else "fail",
        "fallback_pattern_id": pattern_id,
        "evidence_type": spec.evidence_type,
        "evidence_field": "fallback_result",
        "fallback_result": "matched" if match else "not_found",
        "source_ref": rel_path if not match else f"{rel_path}:{line_for_offset(masked, match.start())}",
        "promotion_limit": spec.promotion_limit,
        "parser_backed": False,
        "writes_shadow_docs": False,
    }
    return bool(match), payload


def match_python_call(args: argparse.Namespace, root: Path, spec: PrimarySpec) -> tuple[bool, dict[str, object]]:
    callee = param(args, "callee")
    if not callee:
        raise ProbeError("--callee is required for py.ast.call_match@v1")

    source = resolve_inside(root, args.source_file, "source file")
    rel_path = normalize_rel_path(source, root)
    enforce_primary_path_scope(rel_path, spec)
    tree = ast.parse(read_text(source), filename=rel_path)

    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and name_matches(ast_call_name(node.func), callee):
            return True, primary_payload("pass", "py.ast.call_match@v1", spec, f"{rel_path}:{node.lineno}", "matched")
    return False, primary_payload("fail", "py.ast.call_match@v1", spec, rel_path, "not_found")


def match_python_decorator(args: argparse.Namespace, root: Path, spec: PrimarySpec) -> tuple[bool, dict[str, object]]:
    decorator = param(args, "decorator")
    if not decorator:
        raise ProbeError("--decorator is required for py.decorator.match@v1")

    source = resolve_inside(root, args.source_file, "source file")
    rel_path = normalize_rel_path(source, root)
    enforce_primary_path_scope(rel_path, spec)
    tree = ast.parse(read_text(source), filename=rel_path)

    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            for deco in node.decorator_list:
                target = deco.func if isinstance(deco, ast.Call) else deco
                if name_matches(ast_call_name(target), decorator):
                    return True, primary_payload("pass", "py.decorator.match@v1", spec, f"{rel_path}:{deco.lineno}", "matched")
    return False, primary_payload("fail", "py.decorator.match@v1", spec, rel_path, "not_found")


def primary_payload(status: str, validator_id: str, spec: PrimarySpec, source_ref: str, validator_result: str) -> dict[str, object]:
    return {
        "status": status,
        "validator_id": validator_id,
        "evidence_type": spec.evidence_type,
        "evidence_field": "validator_result",
        "validator_result": validator_result,
        "source_ref": source_ref,
        "validator_kind": spec.kind,
        "parser_backed": spec.parser_backed,
        "promotion_limit": spec.promotion_limit,
        "writes_shadow_docs": False,
    }


def match_source_probe(args: argparse.Namespace, root: Path, validator_id: str, spec: PrimarySpec) -> tuple[bool, dict[str, object]]:
    source = resolve_inside(root, args.source_file, "source file")
    rel_path = normalize_rel_path(source, root)
    enforce_primary_path_scope(rel_path, spec)
    text = read_text(source)
    masked = mask_c_like_code(text)

    if validator_id == "java.annotation.match@v1":
        annotation = param(args, "annotation")
        if not annotation:
            raise ProbeError("--annotation is required for java.annotation.match@v1")
        pattern = re.compile(r"@" + re.escape(annotation) + r"\b")
    elif validator_id == "spring_boot.request_mapping@v1":
        pattern = re.compile(r"@(?:GetMapping|PostMapping|PutMapping|PatchMapping|DeleteMapping|RequestMapping)\b")
    elif validator_id == "spring_boot.cache_evict.annotation@v1":
        pattern = re.compile(r"@CacheEvict\b")
    elif validator_id == "jpa.repository.save@v1":
        pattern = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*Repository\s*\.\s*save(?:AndFlush)?\s*\(")
    else:
        raise ProbeError(f"source probe not implemented for {validator_id}")

    match = pattern.search(masked)
    return bool(match), primary_payload(
        "pass" if match else "fail",
        validator_id,
        spec,
        rel_path if not match else f"{rel_path}:{line_for_offset(masked, match.start())}",
        "matched" if match else "not_found",
    )


def match_runtime_trace(args: argparse.Namespace, root: Path, spec: PrimarySpec) -> tuple[bool, dict[str, object]]:
    if not args.trace_event:
        raise ProbeError("--trace-event is required for any.runtime.trace@v1")
    trace = resolve_inside(root, args.trace_file, "trace file")
    rel_path = normalize_rel_path(trace, root)
    artifact_hash = sha256_file(trace)

    for line_no, line in enumerate(read_text(trace).splitlines(), start=1):
        if line == args.trace_event:
            payload = primary_payload("pass", "any.runtime.trace@v1", spec, f"{rel_path}:{line_no}", "matched")
            payload["trace_ref"] = f"{rel_path}:{line_no}"
            payload["artifact_hash"] = artifact_hash
            return True, payload
    payload = primary_payload("fail", "any.runtime.trace@v1", spec, rel_path, "not_found")
    payload["trace_ref"] = rel_path
    payload["artifact_hash"] = artifact_hash
    return False, payload


def run_primary(args: argparse.Namespace, root: Path) -> int:
    validator_id = args.validator_id
    spec = PRIMARY_VALIDATORS.get(validator_id)
    if spec is None:
        emit({"status": "unsupported", "validator_id": validator_id, "writes_shadow_docs": False})
        return UNSUPPORTED

    if validator_id == "py.ast.call_match@v1":
        matched, payload = match_python_call(args, root, spec)
    elif validator_id == "py.decorator.match@v1":
        matched, payload = match_python_decorator(args, root, spec)
    elif validator_id == "any.runtime.trace@v1":
        matched, payload = match_runtime_trace(args, root, spec)
    else:
        matched, payload = match_source_probe(args, root, validator_id, spec)

    emit(payload)
    return PASS if matched else FAIL


def run_fallback(args: argparse.Namespace, root: Path) -> int:
    pattern_id = args.fallback_pattern_id
    spec = FALLBACK_PATTERNS.get(pattern_id)
    if spec is None:
        emit({"status": "unsupported", "fallback_pattern_id": pattern_id, "writes_shadow_docs": False})
        return UNSUPPORTED

    matched, payload = match_regex_source(args, root, pattern_id, spec)
    emit(payload)
    return PASS if matched else FAIL


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Probe deterministic evidence for shadow effect-map facts.")
    parser.add_argument("--project-root", required=True, help="Project root that bounds source and trace paths.")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--validator-id", help="Primary validator id to run.")
    group.add_argument("--fallback-pattern-id", help="Approved fallback regex id to run.")
    parser.add_argument("--source-file", help="Source file relative to project root, or absolute under it.")
    parser.add_argument("--trace-file", help="Trace/log file relative to project root, or absolute under it.")
    parser.add_argument("--trace-event", help="Exact trace/log line to match.")
    parser.add_argument("--symbol", help="Generic symbol parameter alias.")
    parser.add_argument("--annotation", help="Annotation name without @.")
    parser.add_argument("--decorator", help="Python/TypeScript decorator name without @.")
    parser.add_argument("--callee", help="Function or method callee name.")
    parser.add_argument("--receiver", help="Receiver symbol for receiver.method fallback patterns.")
    parser.add_argument("--method", help="Method symbol for receiver.method fallback patterns.")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        root = Path(args.project_root).resolve(strict=True)
        if not root.is_dir():
            return emit_error("project root must be a directory")
        if args.validator_id:
            return run_primary(args, root)
        return run_fallback(args, root)
    except (OSError, ProbeError, SyntaxError) as exc:
        return emit_error(str(exc), args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
