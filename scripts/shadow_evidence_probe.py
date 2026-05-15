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
    allowed_extensions: tuple[str, ...] = ()
    rejected_extensions: tuple[str, ...] = ()


@dataclass(frozen=True)
class FallbackSpec:
    evidence_type: str
    language: str
    pattern: str | None = None
    required_params: tuple[str, ...] = ()
    allowed_paths: tuple[str, ...] = ()
    excluded_paths: tuple[str, ...] = ()
    promotion_limit: str = "medium"


@dataclass(frozen=True)
class ValidatorAdapter:
    validator_id: str
    spec: PrimarySpec


JS_EXTENSIONS = (".js", ".jsx", ".mjs", ".cjs")
TS_EXTENSIONS = (".ts", ".tsx", ".mts", ".cts")
TS_REJECTED_EXTENSIONS = (".d.ts",)
JS_TS_EXTENSIONS = JS_EXTENSIONS + TS_EXTENSIONS
JS_TS_ALLOWED_PATHS = ("src/**", "app/**", "lib/**", "server/**", "pages/**", "routes/**")
JS_TS_EXCLUDED_PATHS = (
    "**/node_modules/**",
    "**/dist/**",
    "**/build/**",
    "**/coverage/**",
    "**/test/**",
    "**/tests/**",
    "**/__tests__/**",
    "**/*.test.*",
    "**/*.spec.*",
)
PY_SOURCE_ALLOWED_PATHS = ("**/*.py",)
PY_SOURCE_EXCLUDED_PATHS = ("tests/**", ".venv/**", "venv/**", "build/**", "dist/**")
FASTAPI_ROUTE_METHODS = {"get", "post", "put", "patch", "delete", "options", "head"}
EXPRESS_ROUTE_METHODS = {"get", "post", "put", "patch", "delete", "options", "head", "all"}
PROBE_SCRIPT_NAME = "shadow_evidence_probe.py"


class AdapterRegistry:
    """Static registry of primary validators that can actually execute."""

    def __init__(self, adapters: Iterable[ValidatorAdapter]):
        self._adapters = {adapter.validator_id: adapter for adapter in adapters}

    def ids(self) -> tuple[str, ...]:
        return tuple(sorted(self._adapters))

    def get(self, validator_id: str | None) -> ValidatorAdapter | None:
        if not validator_id:
            return None
        return self._adapters.get(validator_id)

    def validate(self, probe_args: dict[str, object], root: Path) -> tuple[bool, dict[str, object]] | None:
        adapter = self.get(probe_args.get("validator_id"))
        if adapter is None:
            return None
        return run_primary_adapter(argparse.Namespace(**probe_args), root, adapter)


PRIMARY_ADAPTERS: tuple[ValidatorAdapter, ...] = (
    ValidatorAdapter("any.runtime.trace@v1", PrimarySpec("runtime_trace", "runtime_trace", False, "high")),
    ValidatorAdapter(
        "java.ast.call_match@v1",
        PrimarySpec(
            "code_call",
            "java_token_parser",
            True,
            "high",
            "java",
            ("src/main/java/**",),
            ("src/test/**", "build/**", "target/**", ".gradle/**"),
        ),
    ),
    ValidatorAdapter(
        "java.annotation.match@v1",
        PrimarySpec(
            "annotation",
            "source_probe",
            False,
            "medium",
            "java",
            ("src/main/java/**",),
            ("src/test/**", "build/**", "target/**", ".gradle/**"),
        ),
    ),
    ValidatorAdapter(
        "spring_boot.request_mapping@v1",
        PrimarySpec(
            "annotation",
            "source_probe",
            False,
            "medium",
            "java",
            ("src/main/java/**",),
            ("src/test/**", "build/**", "target/**", ".gradle/**"),
        ),
    ),
    ValidatorAdapter(
        "spring_boot.cache_evict.annotation@v1",
        PrimarySpec(
            "annotation",
            "source_probe",
            False,
            "medium",
            "java",
            ("src/main/java/**",),
            ("src/test/**", "build/**", "target/**", ".gradle/**"),
        ),
    ),
    ValidatorAdapter(
        "jpa.repository.save@v1",
        PrimarySpec(
            "code_call",
            "source_probe",
            False,
            "medium",
            "java",
            ("src/main/java/**",),
            ("src/test/**", "build/**", "target/**", ".gradle/**"),
        ),
    ),
    ValidatorAdapter(
        "js.ast.call_match@v1",
        PrimarySpec(
            "code_call",
            "js_token_parser",
            True,
            "high",
            "javascript",
            JS_TS_ALLOWED_PATHS,
            JS_TS_EXCLUDED_PATHS,
            JS_EXTENSIONS,
        ),
    ),
    ValidatorAdapter(
        "ts.ast.call_match@v1",
        PrimarySpec(
            "code_call",
            "ts_token_parser",
            True,
            "high",
            "typescript",
            JS_TS_ALLOWED_PATHS,
            JS_TS_EXCLUDED_PATHS + ("**/*.d.ts",),
            TS_EXTENSIONS,
            TS_REJECTED_EXTENSIONS,
        ),
    ),
    ValidatorAdapter(
        "ts.ast.call_match@v2",
        PrimarySpec(
            "code_call",
            "ts_token_parser",
            True,
            "high",
            "typescript",
            JS_TS_ALLOWED_PATHS,
            JS_TS_EXCLUDED_PATHS + ("**/*.d.ts",),
            TS_EXTENSIONS,
            TS_REJECTED_EXTENSIONS,
        ),
    ),
    ValidatorAdapter(
        "express.route@v1",
        PrimarySpec(
            "code_call",
            "js_ts_token_parser",
            True,
            "high",
            "javascript",
            JS_TS_ALLOWED_PATHS,
            JS_TS_EXCLUDED_PATHS + ("**/*.d.ts",),
            JS_TS_EXTENSIONS,
            TS_REJECTED_EXTENSIONS,
        ),
    ),
    ValidatorAdapter(
        "react.effect_hook@v1",
        PrimarySpec(
            "code_call",
            "js_ts_token_parser",
            True,
            "high",
            "javascript",
            JS_TS_ALLOWED_PATHS,
            JS_TS_EXCLUDED_PATHS + ("**/*.d.ts",),
            JS_TS_EXTENSIONS,
            TS_REJECTED_EXTENSIONS,
        ),
    ),
    ValidatorAdapter(
        "py.ast.call_match@v1",
        PrimarySpec(
            "code_call",
            "ast",
            True,
            "high",
            "python",
            PY_SOURCE_ALLOWED_PATHS,
            PY_SOURCE_EXCLUDED_PATHS,
        ),
    ),
    ValidatorAdapter(
        "py.decorator.match@v1",
        PrimarySpec(
            "annotation",
            "ast",
            True,
            "high",
            "python",
            PY_SOURCE_ALLOWED_PATHS,
            PY_SOURCE_EXCLUDED_PATHS,
        ),
    ),
    ValidatorAdapter(
        "fastapi.route@v1",
        PrimarySpec(
            "annotation",
            "ast",
            True,
            "high",
            "python",
            PY_SOURCE_ALLOWED_PATHS,
            PY_SOURCE_EXCLUDED_PATHS,
        ),
    ),
)


ADAPTER_REGISTRY = AdapterRegistry(PRIMARY_ADAPTERS)
PRIMARY_VALIDATORS: dict[str, PrimarySpec] = {adapter.validator_id: adapter.spec for adapter in PRIMARY_ADAPTERS}


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
        allowed_paths=JS_TS_ALLOWED_PATHS,
        excluded_paths=JS_TS_EXCLUDED_PATHS,
    ),
    "ts.regex.decorator_named@v1": FallbackSpec(
        evidence_type="annotation",
        language="typescript",
        pattern=r"@{{decorator}}\b",
        required_params=("decorator",),
        allowed_paths=("src/**", "app/**", "lib/**"),
        excluded_paths=JS_TS_EXCLUDED_PATHS + ("**/*.d.ts",),
    ),
    "ts.regex.call_named@v1": FallbackSpec(
        evidence_type="code_call",
        language="typescript",
        pattern=r"\b{{callee}}\s*\(",
        required_params=("callee",),
        allowed_paths=JS_TS_ALLOWED_PATHS,
        excluded_paths=JS_TS_EXCLUDED_PATHS + ("**/*.d.ts",),
    ),
    "py.regex.call_named@v1": FallbackSpec(
        evidence_type="code_call",
        language="python",
        pattern=r"\b{{callee}}\s*\(",
        required_params=("callee",),
        allowed_paths=PY_SOURCE_ALLOWED_PATHS,
        excluded_paths=PY_SOURCE_EXCLUDED_PATHS,
    ),
    "py.regex.decorator_named@v1": FallbackSpec(
        evidence_type="annotation",
        language="python",
        pattern=r"@{{decorator}}\b",
        required_params=("decorator",),
        allowed_paths=PY_SOURCE_ALLOWED_PATHS,
        excluded_paths=PY_SOURCE_EXCLUDED_PATHS,
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
    if spec.rejected_extensions and rel_path.endswith(spec.rejected_extensions):
        extensions = ", ".join(spec.rejected_extensions)
        raise ProbeError(f"source file extension is rejected for primary validator: {rel_path} ({extensions})")
    if any(path_matches(rel_path, pattern) for pattern in spec.excluded_paths):
        raise ProbeError(f"source file is excluded for primary validator: {rel_path}")
    if spec.allowed_extensions and not rel_path.endswith(spec.allowed_extensions):
        extensions = ", ".join(spec.allowed_extensions)
        raise ProbeError(f"source file extension is not allowed for primary validator: {rel_path} ({extensions})")


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file_handle:
        for chunk in iter(lambda: file_handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return f"sha256:{digest.hexdigest()}"


def sha256_bytes(value: bytes) -> str:
    return f"sha256:{hashlib.sha256(value).hexdigest()}"


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


JS_REGEX_PREFIX_TOKENS = {
    "",
    "(",
    "[",
    "{",
    "=",
    ":",
    ",",
    ";",
    "!",
    "?",
    "&",
    "|",
    "+",
    "-",
    "*",
    "%",
    "^",
    "~",
    "<",
    ">",
}
JS_REGEX_PREFIX_KEYWORDS = {
    "await",
    "case",
    "delete",
    "do",
    "else",
    "in",
    "instanceof",
    "of",
    "return",
    "throw",
    "typeof",
    "void",
    "yield",
}


def previous_js_token(chars: list[str], slash_index: int) -> str:
    index = slash_index - 1
    while index >= 0 and chars[index].isspace():
        index -= 1
    if index < 0:
        return ""
    if re.match(r"[A-Za-z0-9_$]", chars[index]):
        end = index + 1
        while index >= 0 and re.match(r"[A-Za-z0-9_$]", chars[index]):
            index -= 1
        return "".join(chars[index + 1 : end])
    return chars[index]


def is_probable_js_regex_start(chars: list[str], slash_index: int) -> bool:
    previous = previous_js_token(chars, slash_index)
    return previous in JS_REGEX_PREFIX_TOKENS or previous in JS_REGEX_PREFIX_KEYWORDS


def mask_js_regex_literal(chars: list[str], start: int) -> int:
    index = start
    in_class = False
    while index < len(chars):
        c = chars[index]
        if c == "\n":
            return index
        chars[index] = " "
        if c == "\\":
            index += 1
            if index < len(chars) and chars[index] != "\n":
                chars[index] = " "
            index += 1
            continue
        if c == "[":
            in_class = True
        elif c == "]":
            in_class = False
        elif c == "/" and index != start and not in_class:
            index += 1
            while index < len(chars) and re.match(r"[A-Za-z0-9_$]", chars[index]):
                chars[index] = " "
                index += 1
            return index
        index += 1
    return index


def mask_js_ts_code(text: str) -> str:
    chars = list(mask_c_like_code(text))
    index = 0
    while index < len(chars):
        c = chars[index]
        nxt = chars[index + 1] if index + 1 < len(chars) else ""
        if c == "/" and nxt not in {"/", "*"} and is_probable_js_regex_start(chars, index):
            index = mask_js_regex_literal(chars, index)
            continue
        index += 1
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
    if language == "java":
        return mask_c_like_code(text)
    if language in {"javascript", "typescript"}:
        return mask_js_ts_code(text)
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
    source_hash = sha256_file(source)

    text = read_text(source)
    masked = mask_for_language(text, spec.language)
    regex = compile_pattern(spec.pattern or "", args, spec.required_params)
    match = regex.search(masked)
    payload = {
        "status": "pass" if match else "fail",
        "probe_status": "pass" if match else "fail",
        "fact_status": "candidate_only",
        "fallback_pattern_id": pattern_id,
        "evidence_type": spec.evidence_type,
        "evidence_field": "fallback_result",
        "fallback_result": "matched" if match else "not_found",
        "source_ref": rel_path if not match else f"{rel_path}:{line_for_offset(masked, match.start())}",
        "source_hash": source_hash,
        "promotion_limit": spec.promotion_limit,
        "parser_backed": False,
        "writes_shadow_docs": False,
    }
    return bool(match), payload


def match_python_call(args: argparse.Namespace, root: Path, spec: PrimarySpec) -> tuple[bool, dict[str, object]]:
    callee = param(args, "callee")
    if not callee:
        raise ProbeError("--callee is required for py.ast.call_match@v1")
    receiver = param(args, "receiver")

    source = resolve_inside(root, args.source_file, "source file")
    rel_path = normalize_rel_path(source, root)
    enforce_primary_path_scope(rel_path, spec)
    source_hash = sha256_file(source)
    tree = ast.parse(read_text(source), filename=rel_path)

    for node in ast.walk(tree):
        actual_name = ast_call_name(node.func) if isinstance(node, ast.Call) else None
        if not isinstance(node, ast.Call) or not name_matches(actual_name, callee):
            continue
        if receiver and actual_name != f"{receiver}.{callee}":
            continue
        payload = primary_payload(
            "pass", "py.ast.call_match@v1", spec, f"{rel_path}:{node.lineno}", "matched", source_hash
        )
        payload["matched_symbol"] = actual_name or callee
        return True, payload
    return False, primary_payload("fail", "py.ast.call_match@v1", spec, rel_path, "not_found", source_hash)


def match_python_decorator(args: argparse.Namespace, root: Path, spec: PrimarySpec) -> tuple[bool, dict[str, object]]:
    decorator = param(args, "decorator")
    if not decorator:
        raise ProbeError("--decorator is required for py.decorator.match@v1")

    source = resolve_inside(root, args.source_file, "source file")
    rel_path = normalize_rel_path(source, root)
    enforce_primary_path_scope(rel_path, spec)
    source_hash = sha256_file(source)
    tree = ast.parse(read_text(source), filename=rel_path)

    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            for deco in node.decorator_list:
                target = deco.func if isinstance(deco, ast.Call) else deco
                actual_name = ast_call_name(target)
                if name_matches(actual_name, decorator):
                    payload = primary_payload(
                        "pass", "py.decorator.match@v1", spec, f"{rel_path}:{deco.lineno}", "matched", source_hash
                    )
                    payload["matched_symbol"] = actual_name or decorator
                    return True, payload
    return False, primary_payload("fail", "py.decorator.match@v1", spec, rel_path, "not_found", source_hash)


def literal_string_arg(call: ast.Call) -> str | None:
    if not call.args:
        return None
    first_arg = call.args[0]
    if isinstance(first_arg, ast.Constant) and isinstance(first_arg.value, str):
        return first_arg.value
    return None


def fastapi_route_method(decorator_name: str | None) -> str | None:
    if decorator_name is None:
        return None
    method = decorator_name.split(".")[-1]
    return method if method in FASTAPI_ROUTE_METHODS else None


def match_fastapi_route(args: argparse.Namespace, root: Path, spec: PrimarySpec) -> tuple[bool, dict[str, object]]:
    decorator = param(args, "decorator")
    if not decorator:
        raise ProbeError("--decorator is required for fastapi.route@v1")
    if fastapi_route_method(decorator) is None:
        raise ProbeError("--decorator must end with a FastAPI route method for fastapi.route@v1")
    route_path = getattr(args, "route_path", None)

    source = resolve_inside(root, args.source_file, "source file")
    rel_path = normalize_rel_path(source, root)
    enforce_primary_path_scope(rel_path, spec)
    source_hash = sha256_file(source)
    tree = ast.parse(read_text(source), filename=rel_path)

    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        for deco in node.decorator_list:
            if not isinstance(deco, ast.Call):
                continue
            actual_name = ast_call_name(deco.func)
            actual_method = fastapi_route_method(actual_name)
            if actual_method is None or not name_matches(actual_name, decorator):
                continue
            actual_route_path = literal_string_arg(deco)
            if route_path and actual_route_path != route_path:
                continue
            payload = primary_payload(
                "pass", "fastapi.route@v1", spec, f"{rel_path}:{deco.lineno}", "matched", source_hash
            )
            payload["matched_symbol"] = actual_name or decorator
            payload["http_method"] = actual_method
            if actual_route_path is not None:
                payload["route_path"] = actual_route_path
            return True, payload
    return False, primary_payload("fail", "fastapi.route@v1", spec, rel_path, "not_found", source_hash)


def c_like_tokens_from_masked(text: str, masked: str) -> list[tuple[str, str, int]]:
    tokens: list[tuple[str, str, int]] = []
    token_re = re.compile(r"(?P<identifier>[A-Za-z_$][A-Za-z0-9_$]*)|(?P<arrow>=>)|(?P<symbol>[(){};=.,@:\[\]<>?])")
    for match in token_re.finditer(masked):
        kind = "identifier" if match.group("identifier") else "symbol"
        tokens.append((kind, match.group(0), line_for_offset(text, match.start())))
    return tokens


def java_tokens(text: str) -> list[tuple[str, str, int]]:
    return c_like_tokens_from_masked(text, mask_c_like_code(text))


def js_ts_tokens(text: str) -> list[tuple[str, str, int]]:
    return c_like_tokens_from_masked(text, mask_js_ts_code(text))


def js_ts_primary_kind(rel_path: str) -> str:
    return "ts_token_parser" if rel_path.endswith(TS_EXTENSIONS) else "js_token_parser"


def matching_java_paren(tokens: list[tuple[str, str, int]], open_index: int) -> int | None:
    depth = 0
    for index in range(open_index, len(tokens)):
        value = tokens[index][1]
        if value == "(":
            depth += 1
        elif value == ")":
            depth -= 1
            if depth == 0:
                return index
    return None


JAVA_DECLARATION_FOLLOWERS = {"{", "default", "throws"}
JAVA_DECLARATION_PREFIXES = {
    "abstract",
    "boolean",
    "byte",
    "char",
    "class",
    "default",
    "double",
    "final",
    "float",
    "int",
    "long",
    "native",
    "private",
    "protected",
    "public",
    "short",
    "static",
    "strictfp",
    "synchronized",
    "transient",
    "void",
    "volatile",
}
JAVA_CALL_CONTEXT_PREFIXES = {"new", "return", "throw", "if", "while", "for", "switch", "assert"}
JAVA_NON_DECLARATION_PREFIX_TOKENS = {"=", ".", ","}


def java_statement_prefix(tokens: list[tuple[str, str, int]], callee_index: int) -> list[str]:
    start = callee_index - 1
    while start >= 0 and tokens[start][1] not in {";", "{", "}"}:
        start -= 1
    return [value for _, value, _ in tokens[start + 1 : callee_index]]


def is_probable_java_declaration(tokens: list[tuple[str, str, int]], callee_index: int, close_index: int) -> bool:
    next_value = tokens[close_index + 1][1] if close_index + 1 < len(tokens) else None
    prev_value = tokens[callee_index - 1][1] if callee_index > 0 else None
    prefix = java_statement_prefix(tokens, callee_index)

    if next_value in JAVA_DECLARATION_FOLLOWERS:
        return prev_value not in JAVA_CALL_CONTEXT_PREFIXES
    if next_value == ";" and prev_value in JAVA_DECLARATION_PREFIXES:
        return True
    if next_value == ";" and prefix:
        if prefix[0] in JAVA_CALL_CONTEXT_PREFIXES:
            return False
        if not any(token in JAVA_NON_DECLARATION_PREFIX_TOKENS for token in prefix):
            return True
    if next_value == ";" and callee_index >= 2 and tokens[callee_index - 2][1] in {"{", ";", "}"}:
        return prev_value not in JAVA_CALL_CONTEXT_PREFIXES
    return False


def match_java_call(args: argparse.Namespace, root: Path, spec: PrimarySpec) -> tuple[bool, dict[str, object]]:
    callee = param(args, "callee") or param(args, "method")
    if not callee:
        raise ProbeError("--callee is required for java.ast.call_match@v1")
    receiver = param(args, "receiver")

    source = resolve_inside(root, args.source_file, "source file")
    rel_path = normalize_rel_path(source, root)
    enforce_primary_path_scope(rel_path, spec)
    source_hash = sha256_file(source)
    tokens = java_tokens(read_text(source))

    for index, (kind, value, line_no) in enumerate(tokens):
        if kind != "identifier" or value != callee:
            continue
        if index + 1 >= len(tokens) or tokens[index + 1][1] != "(":
            continue
        close_index = matching_java_paren(tokens, index + 1)
        if close_index is None:
            continue
        actual_receiver = None
        if index >= 2 and tokens[index - 1][1] == "." and tokens[index - 2][0] == "identifier":
            actual_receiver = tokens[index - 2][1]
        if receiver and actual_receiver != receiver:
            continue
        if actual_receiver is None and is_probable_java_declaration(tokens, index, close_index):
            continue
        matched_symbol = f"{actual_receiver}.{callee}" if actual_receiver else callee
        payload = primary_payload(
            "pass", "java.ast.call_match@v1", spec, f"{rel_path}:{line_no}", "matched", source_hash
        )
        payload["matched_symbol"] = matched_symbol
        return True, payload
    return False, primary_payload("fail", "java.ast.call_match@v1", spec, rel_path, "not_found", source_hash)


JS_DECLARATION_PREFIXES = {"async", "declare", "function", "get", "interface", "set"}
JS_DECLARATION_FOLLOWERS = {"{", "=>", ":"}


def is_probable_js_declaration(tokens: list[tuple[str, str, int]], callee_index: int, close_index: int) -> bool:
    next_value = tokens[close_index + 1][1] if close_index + 1 < len(tokens) else None
    prev_value = tokens[callee_index - 1][1] if callee_index > 0 else None
    if prev_value in JS_DECLARATION_PREFIXES:
        return True
    if next_value in JS_DECLARATION_FOLLOWERS and prev_value != ".":
        return True
    return False


def receiver_before_call(tokens: list[tuple[str, str, int]], callee_index: int) -> str | None:
    if callee_index >= 2 and tokens[callee_index - 1][1] == "." and tokens[callee_index - 2][0] == "identifier":
        return tokens[callee_index - 2][1]
    if (
        callee_index >= 3
        and tokens[callee_index - 1][1] == "."
        and tokens[callee_index - 2][1] == "?"
        and tokens[callee_index - 3][0] == "identifier"
    ):
        return tokens[callee_index - 3][1]
    return None


def call_open_paren_index(
    tokens: list[tuple[str, str, int]],
    callee_index: int,
    allow_type_arguments: bool,
) -> tuple[int | None, bool]:
    next_index = callee_index + 1
    if next_index >= len(tokens):
        return None, False
    if tokens[next_index][1] == "(":
        return next_index, False
    if not allow_type_arguments or tokens[next_index][1] != "<":
        return None, False

    depth = 0
    saw_type_token = False
    for index in range(next_index, len(tokens)):
        value = tokens[index][1]
        if value in {";", "{", "}"}:
            return None, False
        if value == "<":
            depth += 1
        elif value == ">":
            depth -= 1
            if depth < 0:
                return None, False
            if depth == 0:
                if not saw_type_token:
                    return None, False
                open_index = index + 1
                if open_index < len(tokens) and tokens[open_index][1] == "(":
                    return open_index, True
                return None, False
        elif depth > 0:
            saw_type_token = True
    return None, False


def match_js_ts_call(
    args: argparse.Namespace,
    root: Path,
    spec: PrimarySpec,
    validator_id: str,
) -> tuple[bool, dict[str, object]]:
    callee = param(args, "callee") or param(args, "method")
    if not callee:
        raise ProbeError(f"--callee is required for {validator_id}")
    receiver = param(args, "receiver")

    source = resolve_inside(root, args.source_file, "source file")
    rel_path = normalize_rel_path(source, root)
    enforce_primary_path_scope(rel_path, spec)
    source_hash = sha256_file(source)
    tokens = js_ts_tokens(read_text(source))
    allow_type_arguments = validator_id == "ts.ast.call_match@v2"

    for index, (kind, value, line_no) in enumerate(tokens):
        if kind != "identifier" or value != callee:
            continue
        open_index, matched_type_arguments = call_open_paren_index(tokens, index, allow_type_arguments)
        if open_index is None:
            continue
        close_index = matching_java_paren(tokens, open_index)
        if close_index is None:
            continue
        actual_receiver = receiver_before_call(tokens, index)
        if receiver and actual_receiver != receiver:
            continue
        if actual_receiver is None and is_probable_js_declaration(tokens, index, close_index):
            continue
        matched_symbol = f"{actual_receiver}.{callee}" if actual_receiver else callee
        payload = primary_payload("pass", validator_id, spec, f"{rel_path}:{line_no}", "matched", source_hash)
        payload["matched_symbol"] = matched_symbol
        if matched_type_arguments:
            payload["type_arguments"] = True
        return True, payload
    return False, primary_payload("fail", validator_id, spec, rel_path, "not_found", source_hash)


def skip_js_whitespace_and_comments(text: str, index: int) -> int:
    while index < len(text):
        if text[index].isspace():
            index += 1
            continue
        if text.startswith("//", index):
            newline = text.find("\n", index + 2)
            return len(text) if newline == -1 else skip_js_whitespace_and_comments(text, newline + 1)
        if text.startswith("/*", index):
            end = text.find("*/", index + 2)
            return len(text) if end == -1 else skip_js_whitespace_and_comments(text, end + 2)
        return index
    return index


def literal_js_string_at(text: str, index: int) -> tuple[str, int] | None:
    index = skip_js_whitespace_and_comments(text, index)
    if index >= len(text) or text[index] not in {"'", '"', "`"}:
        return None

    quote = text[index]
    cursor = index + 1
    value_chars: list[str] = []
    while cursor < len(text):
        char = text[cursor]
        if char == "\\":
            return None
        if quote == "`" and char == "$" and cursor + 1 < len(text) and text[cursor + 1] == "{":
            return None
        if char == quote:
            return "".join(value_chars), cursor + 1
        if char in {"\n", "\r"} and quote != "`":
            return None
        value_chars.append(char)
        cursor += 1
    return None


def first_arg_is_complete_literal(text: str, index: int) -> tuple[str, int] | None:
    literal = literal_js_string_at(text, index)
    if literal is None:
        return None
    value, end_index = literal
    next_index = skip_js_whitespace_and_comments(text, end_index)
    if next_index >= len(text) or text[next_index] in {",", ")"}:
        return value, end_index
    return None


EXPRESS_ROUTE_CALL_RE = re.compile(
    r"(?<![A-Za-z0-9_$.?])(?P<receiver>app|router)\s*\.\s*"
    r"(?P<method>get|post|put|patch|delete|options|head|all)\s*\(",
    re.MULTILINE,
)


def match_express_route(args: argparse.Namespace, root: Path, spec: PrimarySpec) -> tuple[bool, dict[str, object]]:
    route_path = getattr(args, "route_path", None)

    source = resolve_inside(root, args.source_file, "source file")
    rel_path = normalize_rel_path(source, root)
    enforce_primary_path_scope(rel_path, spec)
    source_hash = sha256_file(source)
    text = read_text(source)
    masked = mask_js_ts_code(text)

    for match in EXPRESS_ROUTE_CALL_RE.finditer(masked):
        method = match.group("method")
        if method not in EXPRESS_ROUTE_METHODS:
            continue
        literal = first_arg_is_complete_literal(text, match.end())
        if literal is None:
            continue
        actual_route_path, _ = literal
        if route_path and actual_route_path != route_path:
            continue
        matched_symbol = f"{match.group('receiver')}.{method}"
        payload = primary_payload(
            "pass", "express.route@v1", spec, f"{rel_path}:{line_for_offset(masked, match.start())}", "matched", source_hash
        )
        payload["validator_kind"] = js_ts_primary_kind(rel_path)
        refresh_parser_provenance(payload, "express.route@v1")
        payload["matched_symbol"] = matched_symbol
        payload["http_method"] = method
        payload["route_path"] = actual_route_path
        return True, payload

    payload = primary_payload("fail", "express.route@v1", spec, rel_path, "not_found", source_hash)
    payload["validator_kind"] = js_ts_primary_kind(rel_path)
    refresh_parser_provenance(payload, "express.route@v1")
    return False, payload


IMPORT_FROM_RE = re.compile(r"(?<![A-Za-z0-9_$])import\s+(?P<body>.*?)\s+from\b", re.DOTALL)


@dataclass(frozen=True)
class ReactImportBindings:
    named_use_effect: bool
    member_receivers: frozenset[str]


def split_import_specifiers(specifiers: str) -> list[str]:
    return [item.strip() for item in specifiers.split(",") if item.strip()]


def react_import_bindings(text: str, masked: str) -> ReactImportBindings:
    named_use_effect = False
    member_receivers: set[str] = set()

    for match in IMPORT_FROM_RE.finditer(masked):
        literal = literal_js_string_at(text, match.end())
        if literal is None:
            continue
        module_name, _ = literal
        if module_name != "react":
            continue

        body = match.group("body").strip()
        if body.startswith("type "):
            continue

        named_block = re.search(r"\{(?P<specifiers>[^{}]*)\}", body, re.DOTALL)
        if named_block:
            for specifier in split_import_specifiers(named_block.group("specifiers")):
                if specifier == "useEffect":
                    named_use_effect = True

        body_without_named = re.sub(r"\{[^{}]*\}", "", body).strip()
        namespace_match = re.match(r"^\*\s+as\s+([A-Za-z_$][A-Za-z0-9_$]*)(?:\s*,\s*)?$", body_without_named)
        if namespace_match:
            member_receivers.add(namespace_match.group(1))
            continue

        default_match = re.match(r"^([A-Za-z_$][A-Za-z0-9_$]*)(?:\s*,\s*)?$", body_without_named)
        if default_match:
            member_receivers.add(default_match.group(1))

    return ReactImportBindings(named_use_effect=named_use_effect, member_receivers=frozenset(member_receivers))


def direct_receiver_before_call(tokens: list[tuple[str, str, int]], callee_index: int) -> str | None:
    if callee_index >= 2 and tokens[callee_index - 1][1] == "." and tokens[callee_index - 2][0] == "identifier":
        return tokens[callee_index - 2][1]
    return None


def match_react_effect_hook(args: argparse.Namespace, root: Path, spec: PrimarySpec) -> tuple[bool, dict[str, object]]:
    source = resolve_inside(root, args.source_file, "source file")
    rel_path = normalize_rel_path(source, root)
    enforce_primary_path_scope(rel_path, spec)
    source_hash = sha256_file(source)
    text = read_text(source)
    masked = mask_js_ts_code(text)
    bindings = react_import_bindings(text, masked)
    tokens = js_ts_tokens(text)

    for index, (kind, value, line_no) in enumerate(tokens):
        if kind != "identifier" or value != "useEffect":
            continue
        open_index, _ = call_open_paren_index(tokens, index, False)
        if open_index is None:
            continue
        close_index = matching_java_paren(tokens, open_index)
        if close_index is None:
            continue

        actual_receiver = direct_receiver_before_call(tokens, index)
        if actual_receiver is None:
            if not bindings.named_use_effect or is_probable_js_declaration(tokens, index, close_index):
                continue
            matched_symbol = "useEffect"
        elif actual_receiver in bindings.member_receivers:
            if not bindings.member_receivers:
                continue
            matched_symbol = f"{actual_receiver}.useEffect"
        else:
            continue

        payload = primary_payload(
            "pass", "react.effect_hook@v1", spec, f"{rel_path}:{line_no}", "matched", source_hash
        )
        payload["validator_kind"] = js_ts_primary_kind(rel_path)
        refresh_parser_provenance(payload, "react.effect_hook@v1")
        payload["matched_symbol"] = matched_symbol
        return True, payload

    payload = primary_payload("fail", "react.effect_hook@v1", spec, rel_path, "not_found", source_hash)
    payload["validator_kind"] = js_ts_primary_kind(rel_path)
    refresh_parser_provenance(payload, "react.effect_hook@v1")
    return False, payload


def refresh_parser_provenance(payload: dict[str, object], validator_id: str) -> None:
    if payload.get("parser_backed") is True and isinstance(payload.get("validator_kind"), str):
        payload["parser_identity"] = f"{PROBE_SCRIPT_NAME}:{validator_id}:{payload['validator_kind']}"
        payload["parser_content_hash"] = sha256_file(Path(__file__).resolve())


def primary_payload(
    status: str,
    validator_id: str,
    spec: PrimarySpec,
    source_ref: str,
    validator_result: str,
    source_hash: str | None = None,
) -> dict[str, object]:
    payload: dict[str, object] = {
        "status": status,
        "probe_status": status,
        "fact_status": "deterministic_evidence" if spec.parser_backed or spec.evidence_type == "runtime_trace" else "candidate_only",
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
    if source_hash is not None:
        payload["source_hash"] = source_hash
    if spec.parser_backed:
        refresh_parser_provenance(payload, validator_id)
    return payload


def match_source_probe(args: argparse.Namespace, root: Path, validator_id: str, spec: PrimarySpec) -> tuple[bool, dict[str, object]]:
    source = resolve_inside(root, args.source_file, "source file")
    rel_path = normalize_rel_path(source, root)
    enforce_primary_path_scope(rel_path, spec)
    source_hash = sha256_file(source)
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
        source_hash,
    )


def match_runtime_trace(args: argparse.Namespace, root: Path, spec: PrimarySpec) -> tuple[bool, dict[str, object]]:
    if not args.trace_event:
        raise ProbeError("--trace-event is required for any.runtime.trace@v1")
    trace = resolve_inside(root, args.trace_file, "trace file")
    rel_path = normalize_rel_path(trace, root)
    raw_bytes = trace.read_bytes()
    text = raw_bytes.decode("utf-8", errors="replace")
    lines = text.splitlines()

    matched_line_no = None
    for line_no, line in enumerate(lines, start=1):
        if line == args.trace_event:
            matched_line_no = line_no
            break

    artifact_hash = runtime_trace_artifact_hash(args, raw_bytes, lines, matched_line_no)
    if matched_line_no is not None:
        trace_ref = f"{rel_path}:{matched_line_no}"
        payload = primary_payload("pass", "any.runtime.trace@v1", spec, trace_ref, "matched")
        payload["trace_ref"] = trace_ref
        payload["artifact_hash"] = artifact_hash
        payload["hash_input_scope"] = args.hash_input_scope
        add_runtime_scope_payload(args, payload)
        return True, payload
    payload = primary_payload("fail", "any.runtime.trace@v1", spec, rel_path, "not_found")
    payload["trace_ref"] = rel_path
    payload["artifact_hash"] = artifact_hash
    payload["hash_input_scope"] = args.hash_input_scope
    add_runtime_scope_payload(args, payload)
    return False, payload


def runtime_trace_artifact_hash(
    args: argparse.Namespace,
    raw_bytes: bytes,
    lines: list[str],
    matched_line_no: int | None,
) -> str:
    """Return scoped any.runtime.trace@v1 artifact hash.

    Contract matches shadow_effect_writer.py: whole_artifact hashes exact file
    bytes; line_range hashes 1-based inclusive physical lines with original
    terminators preserved; selected_fields hashes a single-line top-level JSON
    object with json.dumps(sort_keys=True, separators=(",", ":")).
    """
    if args.hash_input_scope == "whole_artifact":
        return sha256_bytes(raw_bytes)

    if args.hash_input_scope == "line_range":
        start = args.line_range_start
        end = args.line_range_end
        if start is None or end is None or start < 1 or end < start:
            raise ProbeError("--line-range-start and --line-range-end must satisfy start >= 1 and end >= start")
        if matched_line_no is not None and not (start <= matched_line_no <= end):
            raise ProbeError("matched trace line must be inside the declared line_range")
        byte_lines = raw_bytes.splitlines(keepends=True)
        if end > len(byte_lines):
            raise ProbeError("line_range must be within trace file line count")
        return sha256_bytes(b"".join(byte_lines[start - 1 : end]))

    if args.hash_input_scope == "selected_fields":
        selected_fields = args.selected_field or []
        if not selected_fields:
            raise ProbeError("--selected-field is required for selected_fields scope")
        if len(set(selected_fields)) != len(selected_fields):
            raise ProbeError("--selected-field must not contain duplicates")
        if any(not field or "." in field for field in selected_fields):
            raise ProbeError("selected_fields scope supports only top-level field names")
        if matched_line_no != 1 or len(lines) != 1 or lines[0] != args.trace_event:
            raise ProbeError("selected_fields scope requires the matched trace line to be the single JSON artifact line")
        try:
            text = raw_bytes.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise ProbeError(f"selected_fields scope requires UTF-8 JSON: {exc}") from exc
        try:
            parsed = parse_top_level_json_object_without_duplicates(text)
        except json.JSONDecodeError as exc:
            raise ProbeError(f"selected_fields scope requires valid JSON: {exc}") from exc
        except ValueError as exc:
            raise ProbeError(f"selected_fields scope requires {exc}") from exc
        missing = [field for field in selected_fields if field not in parsed]
        if missing:
            raise ProbeError("selected_fields scope requires every selected field to exist")
        selected = {field: parsed[field] for field in selected_fields}
        return sha256_bytes(json.dumps(selected, sort_keys=True, separators=(",", ":")).encode("utf-8"))

    raise ProbeError("--hash-input-scope must be whole_artifact, line_range, or selected_fields")


def parse_top_level_json_object_without_duplicates(text: str) -> dict[str, object]:
    def reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
        result: dict[str, object] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("no duplicate top-level field names")
            result[key] = value
        return result

    parsed = json.loads(text, object_pairs_hook=reject_duplicate_keys)
    if not isinstance(parsed, dict):
        raise ValueError("a JSON object")
    return parsed


def add_runtime_scope_payload(args: argparse.Namespace, payload: dict[str, object]) -> None:
    if args.hash_input_scope == "line_range":
        payload["line_range"] = {"start": args.line_range_start, "end": args.line_range_end}
    if args.hash_input_scope == "selected_fields":
        payload["selected_fields"] = args.selected_field or []


def run_primary_adapter(args: argparse.Namespace, root: Path, adapter: ValidatorAdapter) -> tuple[bool, dict[str, object]]:
    validator_id = adapter.validator_id
    spec = adapter.spec
    if validator_id == "py.ast.call_match@v1":
        matched, payload = match_python_call(args, root, spec)
    elif validator_id == "py.decorator.match@v1":
        matched, payload = match_python_decorator(args, root, spec)
    elif validator_id == "fastapi.route@v1":
        matched, payload = match_fastapi_route(args, root, spec)
    elif validator_id == "java.ast.call_match@v1":
        matched, payload = match_java_call(args, root, spec)
    elif validator_id in {"js.ast.call_match@v1", "ts.ast.call_match@v1", "ts.ast.call_match@v2"}:
        matched, payload = match_js_ts_call(args, root, spec, validator_id)
    elif validator_id == "express.route@v1":
        matched, payload = match_express_route(args, root, spec)
    elif validator_id == "react.effect_hook@v1":
        matched, payload = match_react_effect_hook(args, root, spec)
    elif validator_id == "any.runtime.trace@v1":
        matched, payload = match_runtime_trace(args, root, spec)
    else:
        matched, payload = match_source_probe(args, root, validator_id, spec)
    return matched, payload


def primary_probe_args(args: argparse.Namespace) -> dict[str, object]:
    return {
        "validator_id": args.validator_id,
        "source_file": args.source_file,
        "trace_file": args.trace_file,
        "trace_event": args.trace_event,
        "hash_input_scope": args.hash_input_scope,
        "line_range_start": args.line_range_start,
        "line_range_end": args.line_range_end,
        "selected_field": args.selected_field,
        "symbol": args.symbol,
        "annotation": args.annotation,
        "decorator": args.decorator,
        "route_path": args.route_path,
        "callee": args.callee,
        "receiver": args.receiver,
        "method": args.method,
    }


def run_primary(args: argparse.Namespace, root: Path) -> int:
    validator_id = args.validator_id
    result = ADAPTER_REGISTRY.validate(primary_probe_args(args), root)
    if result is None:
        emit({"status": "unsupported", "validator_id": validator_id, "writes_shadow_docs": False})
        return UNSUPPORTED

    matched, payload = result

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
    parser.add_argument(
        "--hash-input-scope",
        choices=("whole_artifact", "line_range", "selected_fields"),
        default="whole_artifact",
        help="Trace artifact bytes to hash for any.runtime.trace@v1.",
    )
    parser.add_argument("--line-range-start", type=int, help="1-based inclusive start line for line_range hashing.")
    parser.add_argument("--line-range-end", type=int, help="1-based inclusive end line for line_range hashing.")
    parser.add_argument(
        "--selected-field",
        action="append",
        help="Top-level JSON field to include for selected_fields hashing. Repeat for multiple fields.",
    )
    parser.add_argument("--symbol", help="Generic symbol parameter alias.")
    parser.add_argument("--annotation", help="Annotation name without @.")
    parser.add_argument("--decorator", help="Python/TypeScript decorator name without @.")
    parser.add_argument("--route-path", help="Expected literal route path for route validators.")
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
