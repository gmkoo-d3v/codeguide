#!/usr/bin/env bats

load codeguide_helper

@test "shadow_evidence_probe returns unsupported for unknown validator without guessing" {
  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v99"

  [ "$status" -eq 2 ]
  assert_contains "$output" '"status":"unsupported"'
  assert_contains "$output" '"validator_id":"java.ast.call_match@v99"'
}

@test "shadow_evidence_probe uses Python AST for real calls and ignores comments or strings" {
  local parser_content_hash
  parser_content_hash="$(sha256_file_ref "$SHADOW_PROBE")"

  mkdir -p "$TEST_PROJECT/src"
  cat > "$TEST_PROJECT/src/app.py" <<'EOF'
# delete_user()
text = "delete_user()"

def handler(service):
    service.save_user()
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "py.ast.call_match@v1" \
    --source-file "src/app.py" \
    --callee "save_user"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"parser_backed":true'
  assert_contains "$output" '"validator_result":"matched"'
  assert_contains "$output" '"source_hash":"sha256:'
  assert_contains "$output" '"parser_identity":"shadow_evidence_probe.py:py.ast.call_match@v1:ast"'
  assert_contains "$output" '"parser_content_hash":"'"$parser_content_hash"'"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "py.ast.call_match@v1" \
    --source-file "src/app.py" \
    --callee "delete_user"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'
  assert_contains "$output" '"parser_identity":"shadow_evidence_probe.py:py.ast.call_match@v1:ast"'
}

@test "shadow_evidence_probe rejects Python AST primary evidence from test paths" {
  mkdir -p "$TEST_PROJECT/tests"
  cat > "$TEST_PROJECT/tests/test_app.py" <<'EOF'
def test_handler():
    save_user()
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "py.ast.call_match@v1" \
    --source-file "tests/test_app.py" \
    --callee "save_user"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'
  assert_contains "$output" '"validator_id":"py.ast.call_match@v1"'
  assert_contains "$output" "primary validator"
}

@test "shadow_evidence_probe uses Python AST for real decorators" {
  mkdir -p "$TEST_PROJECT/src"
  cat > "$TEST_PROJECT/src/routes.py" <<'EOF'
class Router:
    def post(self, path):
        def wrapper(fn):
            return fn
        return wrapper

router = Router()

@router.post("/users")
def create_user():
    return None
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "py.decorator.match@v1" \
    --source-file "src/routes.py" \
    --decorator "router.post"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"parser_backed":true'
}

@test "shadow_evidence_probe FastAPI route parser-backed matcher validates decorator and literal route path" {
  mkdir -p "$TEST_PROJECT/src" "$TEST_PROJECT/tests"
  cat > "$TEST_PROJECT/src/routes.py" <<'EOF'
from fastapi import FastAPI

app = FastAPI()

@app.post("/users")
async def create_user():
    return {"ok": True}

@app.get("/health")
def health():
    return {"status": "ok"}

@app.api_route("/api-route", methods=["POST"])
def api_route_user():
    return {"ok": True}
EOF
  cat > "$TEST_PROJECT/tests/routes.py" <<'EOF'
@app.post("/users")
def test_create_user():
    return None
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "fastapi.route@v1" \
    --source-file "src/routes.py" \
    --decorator "app.post" \
    --route-path "/users"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"validator_id":"fastapi.route@v1"'
  assert_contains "$output" '"validator_kind":"ast"'
  assert_contains "$output" '"parser_backed":true'
  assert_contains "$output" '"matched_symbol":"app.post"'
  assert_contains "$output" '"http_method":"post"'
  assert_contains "$output" '"route_path":"/users"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "fastapi.route@v1" \
    --source-file "src/routes.py" \
    --decorator "app.post" \
    --route-path "/missing"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "fastapi.route@v1" \
    --source-file "tests/routes.py" \
    --decorator "app.post" \
    --route-path "/users"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'
  assert_contains "$output" "primary validator"

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "fastapi.route@v1" \
    --source-file "src/routes.py" \
    --decorator "app.api_route" \
    --route-path "/api-route"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'
  assert_contains "$output" "FastAPI route method"
}

@test "shadow_evidence_probe fastapi.dependency@v1 parser-backed matcher validates explicit route dependencies" {
  mkdir -p "$TEST_PROJECT/src" "$TEST_PROJECT/tests"
  cat > "$TEST_PROJECT/src/routes.py" <<'EOF'
from typing import Annotated
from fastapi import Depends, FastAPI

app = FastAPI()

def get_current_user():
    return "user"

def audit_dependency():
    return None

@app.get("/default")
def default_dependency(user = Depends(get_current_user)):
    return {"user": user}

@app.post("/annotated")
def annotated_dependency(user: Annotated[str, Depends(get_current_user)]):
    return {"user": user}

@app.delete("/decorator", dependencies=[Depends(audit_dependency)])
def decorator_dependency():
    return {"ok": True}
EOF
  cat > "$TEST_PROJECT/src/plain_depends.py" <<'EOF'
from fastapi import Depends

def get_current_user():
    return "user"

def helper(user = Depends(get_current_user)):
    return user
EOF
  cat > "$TEST_PROJECT/src/non_fastapi_route.py" <<'EOF'
from fastapi import Depends

class Client:
    def get(self, path):
        return lambda fn: fn

client = Client()

def get_current_user():
    return "user"

@client.get("/not-fastapi")
def helper(user = Depends(get_current_user)):
    return user
EOF
  cat > "$TEST_PROJECT/src/local_fastapi_names.py" <<'EOF'
class FastAPI:
    def get(self, path):
        return lambda fn: fn

def Depends(dependency):
    return dependency

app = FastAPI()

def get_current_user():
    return "user"

@app.get("/local")
def helper(user = Depends(get_current_user)):
    return user
EOF
  cat > "$TEST_PROJECT/tests/routes.py" <<'EOF'
from fastapi import Depends

@app.get("/test-only")
def test_dependency(user = Depends(get_current_user)):
    return user
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "fastapi.dependency@v1" \
    --source-file "src/routes.py"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"validator_id":"fastapi.dependency@v1"'
  assert_contains "$output" '"evidence_type":"code_reference"'
  assert_contains "$output" '"validator_kind":"ast"'
  assert_contains "$output" '"parser_backed":true'
  assert_contains "$output" '"matched_symbol":"get_current_user"'
  assert_contains "$output" '"parser_identity":"shadow_evidence_probe.py:fastapi.dependency@v1:ast"'

  cat > "$TEST_PROJECT/src/routes.py" <<'EOF'
from typing import Annotated
from fastapi import Depends, FastAPI

app = FastAPI()

def get_current_user():
    return "user"

@app.post("/annotated")
def annotated_dependency(user: Annotated[str, Depends(get_current_user)]):
    return {"user": user}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "fastapi.dependency@v1" \
    --source-file "src/routes.py"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"matched_symbol":"get_current_user"'

  cat > "$TEST_PROJECT/src/routes.py" <<'EOF'
from fastapi import Depends, FastAPI

app = FastAPI()

def audit_dependency():
    return None

@app.delete("/decorator", dependencies=[Depends(audit_dependency)])
def decorator_dependency():
    return {"ok": True}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "fastapi.dependency@v1" \
    --source-file "src/routes.py"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"matched_symbol":"audit_dependency"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "fastapi.dependency@v1" \
    --source-file "src/plain_depends.py"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "fastapi.dependency@v1" \
    --source-file "src/local_fastapi_names.py"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "fastapi.dependency@v1" \
    --source-file "src/non_fastapi_route.py"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "fastapi.dependency@v1" \
    --source-file "tests/routes.py"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'
  assert_contains "$output" "primary validator"
}

@test "shadow_evidence_probe express.route@v1 tier1 parser-backed route matcher validates literal routes and rejects non-routes" {
  mkdir -p "$TEST_PROJECT/src" "$TEST_PROJECT/tests"
  cat > "$TEST_PROJECT/src/routes.js" <<'EOF'
const express = require("express");
const app = express();

app.get('/users', handler);

function handler(req, res) {
  res.json({ok: true});
}
EOF
  cat > "$TEST_PROJECT/src/routes.ts" <<'EOF'
import express from "express";
const router = express.Router();

router.post('/users', handler);

function handler(req, res) {
  res.json({ok: true});
}
EOF
  cat > "$TEST_PROJECT/src/use-only.js" <<'EOF'
function handler(req, res, next) {
  next();
}

app.use(handler);
EOF
  cat > "$TEST_PROJECT/src/dynamic-route.js" <<'EOF'
const routePath = '/users';

router.post(routePath, handler);
EOF
  cat > "$TEST_PROJECT/src/masked-route-text.js" <<'EOF'
// app.get('/users', handler)
const sample = "router.post('/users', handler)";
const pattern = /app.get\('\/users'/;
EOF
  cat > "$TEST_PROJECT/tests/routes.js" <<'EOF'
app.get('/users', handler);
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "express.route@v1" \
    --source-file "src/routes.js" \
    --route-path "/users"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"validator_id":"express.route@v1"'
  assert_contains "$output" '"validator_result":"matched"'
  assert_contains "$output" '"matched_symbol":"app.get"'
  assert_contains "$output" '"http_method":"get"'
  assert_contains "$output" '"route_path":"/users"'
  assert_contains "$output" '"parser_backed":true'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "express.route@v1" \
    --source-file "src/routes.ts" \
    --route-path "/users"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"validator_kind":"ts_token_parser"'
  assert_contains "$output" '"parser_identity":"shadow_evidence_probe.py:express.route@v1:ts_token_parser"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "express.route@v1" \
    --source-file "src/routes.js" \
    --route-path "/missing"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "express.route@v1" \
    --source-file "src/use-only.js"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "express.route@v1" \
    --source-file "src/dynamic-route.js" \
    --route-path "/users"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "express.route@v1" \
    --source-file "src/masked-route-text.js" \
    --route-path "/users"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "express.route@v1" \
    --source-file "tests/routes.js" \
    --route-path "/users"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'
  assert_contains "$output" "primary validator"
}

@test "shadow_evidence_probe react.effect_hook@v1 tier1 parser-backed matcher validates React imports and rejects non-hooks" {
  mkdir -p "$TEST_PROJECT/src" "$TEST_PROJECT/tests"
  cat > "$TEST_PROJECT/src/named.jsx" <<'EOF'
import { useEffect } from 'react';

export function NamedEffect() {
  useEffect(() => {});
  return null;
}
EOF
  cat > "$TEST_PROJECT/src/namespace.jsx" <<'EOF'
import * as R from 'react';

export function NamespaceEffect() {
  R.useEffect(() => {});
  return null;
}
EOF
  cat > "$TEST_PROJECT/src/default.jsx" <<'EOF'
import R from 'react';

export function DefaultEffect() {
  R.useEffect(() => {});
  return null;
}
EOF
  cat > "$TEST_PROJECT/src/aliased.jsx" <<'EOF'
import { useEffect as fx } from 'react';

export function AliasedEffect() {
  fx(() => {});
  return null;
}
EOF
  cat > "$TEST_PROJECT/src/rebound.jsx" <<'EOF'
const e = React.useEffect;

export function ReboundEffect() {
  e(() => {});
  return null;
}
EOF
  cat > "$TEST_PROJECT/src/non-react.jsx" <<'EOF'
import { useEffect } from 'preact/hooks';
import R from 'preact/compat';

export function NonReactEffect() {
  useEffect(() => {});
  R.useEffect(() => {});
  return null;
}
EOF
  cat > "$TEST_PROJECT/src/masked.jsx" <<'EOF'
// import { useEffect } from 'react'; useEffect(() => {});
const sample = "import { useEffect } from 'react'; useEffect(() => {})";
const pattern = /useEffect\(/;
EOF
  cat > "$TEST_PROJECT/tests/effect.spec.jsx" <<'EOF'
import { useEffect } from 'react';

useEffect(() => {});
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/named.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"validator_id":"react.effect_hook@v1"'
  assert_contains "$output" '"validator_result":"matched"'
  assert_contains "$output" '"matched_symbol":"useEffect"'
  assert_contains "$output" '"dependency_status":"absent_argument"'
  assert_contains "$output" '"parser_backed":true'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/namespace.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"matched_symbol":"R.useEffect"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/default.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"matched_symbol":"R.useEffect"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/aliased.jsx"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/rebound.jsx"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/non-react.jsx"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/masked.jsx"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "tests/effect.spec.jsx"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'
  assert_contains "$output" "primary validator"
}

@test "shadow_evidence_probe react.effect_hook@v1 reports dependency_status syntax metadata" {
  mkdir -p "$TEST_PROJECT/src"
  cat > "$TEST_PROJECT/src/deps-absent.jsx" <<'EOF'
import { useEffect } from 'react';

export function EffectDeps() {
  useEffect(() => {});
  return null;
}
EOF
  cat > "$TEST_PROJECT/src/deps-zero-args.jsx" <<'EOF'
import { useEffect } from 'react';

export function EffectDeps() {
  useEffect();
  return null;
}
EOF
  cat > "$TEST_PROJECT/src/deps-empty.jsx" <<'EOF'
import { useEffect } from 'react';

export function EffectDeps() {
  useEffect(() => {}, []);
  return null;
}
EOF
  cat > "$TEST_PROJECT/src/deps-identifiers.jsx" <<'EOF'
import { useEffect } from 'react';

export function EffectDeps({ userId, ready }) {
  useEffect(() => {}, [userId, ready]);
  return null;
}
EOF
  cat > "$TEST_PROJECT/src/deps-members.jsx" <<'EOF'
import { useEffect } from 'react';

export function EffectDeps({ props, state }) {
  useEffect(() => {}, [props.user, state.value]);
  return null;
}
EOF
  cat > "$TEST_PROJECT/src/deps-non-array-literal.jsx" <<'EOF'
import { useEffect } from 'react';

export function EffectDeps() {
  useEffect(() => {}, true);
  return null;
}
EOF
  cat > "$TEST_PROJECT/src/deps-numeric-literal.jsx" <<'EOF'
import { useEffect } from 'react';

export function EffectDeps() {
  useEffect(() => {}, 1);
  return null;
}
EOF
  cat > "$TEST_PROJECT/src/deps-spread.jsx" <<'EOF'
import { useEffect } from 'react';

export function EffectDeps({ deps }) {
  useEffect(() => {}, [...deps]);
  return null;
}
EOF
  cat > "$TEST_PROJECT/src/deps-computed.jsx" <<'EOF'
import { useEffect } from 'react';

export function EffectDeps({ items, index }) {
  useEffect(() => {}, [items[index]]);
  return null;
}
EOF
  cat > "$TEST_PROJECT/src/deps-alias.jsx" <<'EOF'
import { useEffect } from 'react';

export function EffectDeps({ deps }) {
  useEffect(() => {}, deps);
  return null;
}
EOF
  cat > "$TEST_PROJECT/src/deps-unknown.jsx" <<'EOF'
import { useEffect } from 'react';

export function EffectDeps() {
  useEffect(() => {}, computeDeps());
  return null;
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/deps-absent.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"matched_symbol":"useEffect"'
  assert_contains "$output" '"dependency_status":"absent_argument"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/deps-zero-args.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"matched_symbol":"useEffect"'
  assert_contains "$output" '"dependency_status":"missing_or_non_array_unknown"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/deps-empty.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"matched_symbol":"useEffect"'
  assert_contains "$output" '"dependency_status":"empty_array"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/deps-identifiers.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"matched_symbol":"useEffect"'
  assert_contains "$output" '"dependency_status":"literal_identifier"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/deps-members.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"matched_symbol":"useEffect"'
  assert_contains "$output" '"dependency_status":"member_expression"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/deps-non-array-literal.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"matched_symbol":"useEffect"'
  assert_contains "$output" '"dependency_status":"non_array_literal"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/deps-numeric-literal.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"matched_symbol":"useEffect"'
  assert_contains "$output" '"dependency_status":"non_array_literal"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/deps-spread.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"matched_symbol":"useEffect"'
  assert_contains "$output" '"dependency_status":"spread_or_computed_unsupported"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/deps-computed.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"matched_symbol":"useEffect"'
  assert_contains "$output" '"dependency_status":"spread_or_computed_unsupported"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/deps-alias.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"matched_symbol":"useEffect"'
  assert_contains "$output" '"dependency_status":"destructured_or_alias_unknown"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.effect_hook@v1" \
    --source-file "src/deps-unknown.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"matched_symbol":"useEffect"'
  assert_contains "$output" '"dependency_status":"missing_or_non_array_unknown"'
}

@test "shadow_evidence_probe react.jsx_event_binding@v1 reports syntax-only event binding metadata" {
  mkdir -p "$TEST_PROJECT/src"
  cat > "$TEST_PROJECT/src/direct-identifier.jsx" <<'EOF'
export function Button({ handleClick }) {
  return <button onClick={handleClick} data-id="save" />;
}
EOF
  cat > "$TEST_PROJECT/src/direct-member.jsx" <<'EOF'
export function Button({ props }) {
  return <button onClick={props.handleClick} />;
}
EOF
  cat > "$TEST_PROJECT/src/inline-function.jsx" <<'EOF'
export function Button({ save }) {
  return <button onClick={() => save()} />;
}
EOF
  cat > "$TEST_PROJECT/src/conditional.jsx" <<'EOF'
export function Button({ enabled, save, noop }) {
  return <button onClick={enabled ? save : noop} />;
}
EOF
  cat > "$TEST_PROJECT/src/computed.jsx" <<'EOF'
export function Button({ handlers, name }) {
  return <button onClick={handlers[name]} />;
}
EOF
  cat > "$TEST_PROJECT/src/spread.jsx" <<'EOF'
export function Button({ props }) {
  return <button {...props} />;
}
EOF
  cat > "$TEST_PROJECT/src/nonallowlisted.jsx" <<'EOF'
export function Button({ handleClick, handleHover }) {
  return <button onclick={handleClick} onÅction={handleHover} />;
}
EOF
  cat > "$TEST_PROJECT/src/no-events.jsx" <<'EOF'
export function Label() {
  return <section className="panel"><span data-id="label" /></section>;
}
EOF
  cat > "$TEST_PROJECT/src/no-jsx.js" <<'EOF'
export function add(a, b) {
  return a + b;
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.jsx_event_binding@v1" \
    --source-file "src/direct-identifier.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"validator_id":"react.jsx_event_binding@v1"'
  assert_contains "$output" '"validator_result":"matched"'
  assert_contains "$output" '"event_prop":"onClick"'
  assert_contains "$output" '"event_handler_binding_status":"direct_identifier"'
  assert_contains "$output" '"promotion_limit":"none"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.jsx_event_binding@v1" \
    --source-file "src/direct-member.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"event_handler_binding_status":"direct_member_expression"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.jsx_event_binding@v1" \
    --source-file "src/inline-function.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"event_handler_binding_status":"inline_function_unknown"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.jsx_event_binding@v1" \
    --source-file "src/conditional.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"event_handler_binding_status":"conditional_unknown"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.jsx_event_binding@v1" \
    --source-file "src/computed.jsx"

  [ "$status" -eq 2 ]
  assert_contains "$output" '"status":"unsupported"'
  assert_contains "$output" '"event_handler_binding_status":"computed_or_spread_unsupported"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.jsx_event_binding@v1" \
    --source-file "src/spread.jsx"

  [ "$status" -eq 2 ]
  assert_contains "$output" '"status":"unsupported"'
  assert_contains "$output" '"event_handler_binding_status":"computed_or_spread_unsupported"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.jsx_event_binding@v1" \
    --source-file "src/nonallowlisted.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"validator_result":"non_allowlisted_event_like_prop"'
  assert_contains "$output" '"event_handler_binding_status":"non_allowlisted_event_like_prop"'
  assert_contains "$output" '"event_prop":"onclick"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.jsx_event_binding@v1" \
    --source-file "src/no-events.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"validator_result":"absent"'
  assert_contains "$output" '"event_handler_binding_status":"absent"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.jsx_event_binding@v1" \
    --source-file "src/no-jsx.js"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'
}

@test "shadow_evidence_probe react.jsx_event_binding@v1 ignores non-event props and rejects excluded test paths" {
  mkdir -p "$TEST_PROJECT/src" "$TEST_PROJECT/tests"
  cat > "$TEST_PROJECT/src/props-only.jsx" <<'EOF'
export function Input() {
  return <input className="field" data-testid="name" aria-label="Name" />;
}
EOF
  cat > "$TEST_PROJECT/tests/click.spec.jsx" <<'EOF'
export function TestButton({ click }) {
  return <button onClick={click} />;
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.jsx_event_binding@v1" \
    --source-file "src/props-only.jsx"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"validator_result":"absent"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "react.jsx_event_binding@v1" \
    --source-file "tests/click.spec.jsx"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'
  assert_contains "$output" "primary validator"
}

@test "shadow_evidence_probe regex fallback emits fallback_result only" {
  mkdir -p "$TEST_PROJECT/src/main/java/example"
  cat > "$TEST_PROJECT/src/main/java/example/UserService.java" <<'EOF'
package example;

class UserService {
  void update(User user) {
    // auditRepository.save(user);
    String sample = "auditRepository.save(user)";
    userRepository.save(user);
  }
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --fallback-pattern-id "java.regex.repository_save_call@v1" \
    --source-file "src/main/java/example/UserService.java"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"probe_status":"pass"'
  assert_contains "$output" '"fact_status":"candidate_only"'
  assert_contains "$output" '"fallback_result":"matched"'
  assert_contains "$output" '"evidence_field":"fallback_result"'
  assert_contains "$output" '"source_hash":"sha256:'
  refute_contains "$output" '"validator_result"'
}

@test "shadow_evidence_probe JavaScript regex fallback accepts synced non-src roots" {
  mkdir -p "$TEST_PROJECT/server" "$TEST_PROJECT/pages" "$TEST_PROJECT/routes"
  cat > "$TEST_PROJECT/server/routes.js" <<'EOF'
export function register(apiClient) {
  apiClient.post("/users");
}
EOF
  cat > "$TEST_PROJECT/pages/api.js" <<'EOF'
export default function handler(apiClient) {
  apiClient.post("/users");
}
EOF
  cat > "$TEST_PROJECT/routes/users.js" <<'EOF'
export function users(apiClient) {
  apiClient.post("/users");
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --fallback-pattern-id "js.regex.call_named@v1" \
    --source-file "server/routes.js" \
    --callee "post"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"fallback_result":"matched"'
  assert_contains "$output" '"source_ref":"server/routes.js:2"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --fallback-pattern-id "js.regex.call_named@v1" \
    --source-file "pages/api.js" \
    --callee "post"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"fallback_result":"matched"'
  assert_contains "$output" '"source_ref":"pages/api.js:2"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --fallback-pattern-id "js.regex.call_named@v1" \
    --source-file "routes/users.js" \
    --callee "post"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"fallback_result":"matched"'
  assert_contains "$output" '"source_ref":"routes/users.js:2"'
}

@test "shadow_evidence_probe Java primary source_probe is scoped and non-parser-backed" {
  mkdir -p "$TEST_PROJECT/src/main/java/example"
  cat > "$TEST_PROJECT/src/main/java/example/UserService.java" <<'EOF'
package example;

class UserService {
  void update(User user) {
    userRepository.save(user);
  }
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "jpa.repository.save@v1" \
    --source-file "src/main/java/example/UserService.java"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"probe_status":"pass"'
  assert_contains "$output" '"fact_status":"candidate_only"'
  assert_contains "$output" '"validator_kind":"source_probe"'
  assert_contains "$output" '"parser_backed":false'
  assert_contains "$output" '"promotion_limit":"medium"'
  assert_contains "$output" '"source_hash":"sha256:'
  refute_contains "$output" '"parser_identity"'
  refute_contains "$output" '"parser_content_hash"'
}

@test "shadow_evidence_probe Java parser-backed call matcher ignores comments and strings" {
  mkdir -p "$TEST_PROJECT/src/main/java/example"
  cat > "$TEST_PROJECT/src/main/java/example/UserService.java" <<'EOF'
package example;

class UserService {
  void update(User user) {
    // userRepository.delete(user);
    String text = "userRepository.delete(user)";
    userRepository.save(user);
  }
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v1" \
    --source-file "src/main/java/example/UserService.java" \
    --callee "save" \
    --receiver "userRepository"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"probe_status":"pass"'
  assert_contains "$output" '"fact_status":"deterministic_evidence"'
  assert_contains "$output" '"validator_kind":"java_token_parser"'
  assert_contains "$output" '"parser_backed":true'
  assert_contains "$output" '"matched_symbol":"userRepository.save"'
  assert_contains "$output" '"source_hash":"sha256:'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v1" \
    --source-file "src/main/java/example/UserService.java" \
    --callee "delete" \
    --receiver "userRepository"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'
}

@test "shadow_evidence_probe Java parser-backed call matcher rejects declarations and test paths" {
  mkdir -p "$TEST_PROJECT/src/main/java/example" "$TEST_PROJECT/src/test/java/example"
  cat > "$TEST_PROJECT/src/main/java/example/UserService.java" <<'EOF'
package example;

@interface UserAnnotation {
  String value() default "";
}

interface UserPort {
  User save(User user);
}

abstract class AbstractUserService {
  public abstract User save(User user);
}

class UserService {
  UserService(User user) {}
  void save(User user) {}
  void update(User user) {
    save(user);
  }
}
EOF
  cat > "$TEST_PROJECT/src/test/java/example/UserServiceTest.java" <<'EOF'
package example;

class UserServiceTest {
  void update(User user) {
    userRepository.save(user);
  }
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v1" \
    --source-file "src/main/java/example/UserService.java" \
    --callee "save"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"matched_symbol":"save"'
  assert_contains "$output" '"source_ref":"src/main/java/example/UserService.java:19"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v1" \
    --source-file "src/main/java/example/UserService.java" \
    --callee "UserService"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v1" \
    --source-file "src/main/java/example/UserService.java" \
    --callee "value"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v1" \
    --source-file "src/main/java/example/UserService.java" \
    --callee "save" \
    --receiver "missingReceiver"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v1" \
    --source-file "src/test/java/example/UserServiceTest.java" \
    --callee "save" \
    --receiver "userRepository"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'
  assert_contains "$output" "outside allowed_paths"
}

@test "shadow_evidence_probe Java parser-backed call matcher handles generic-style syntax" {
  mkdir -p "$TEST_PROJECT/src/main/java/example"
  cat > "$TEST_PROJECT/src/main/java/example/UserService.java" <<'EOF'
package example;

import java.util.Optional;

class UserService {
  Optional<User> update(User user) {
    Optional<User> saved = Optional.of(userRepository.save(user));
    return saved;
  }
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v1" \
    --source-file "src/main/java/example/UserService.java" \
    --callee "save" \
    --receiver "userRepository"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"matched_symbol":"userRepository.save"'
}

@test "shadow_evidence_probe JavaScript parser-backed call matcher ignores comments strings declarations and test paths" {
  mkdir -p "$TEST_PROJECT/src"
  cat > "$TEST_PROJECT/src/client.js" <<'EOF'
// apiClient.delete("/users/1")
const sample = "apiClient.delete('/users/1')";

function deleteUser(id) {
  return id;
}

const routes = {
  deleteUser(id) {
    return id;
  }
};

async function handler(apiClient) {
  await apiClient.post("/users");
  fetch("/health");
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "js.ast.call_match@v1" \
    --source-file "src/client.js" \
    --callee "post" \
    --receiver "apiClient"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"fact_status":"deterministic_evidence"'
  assert_contains "$output" '"validator_kind":"js_token_parser"'
  assert_contains "$output" '"parser_backed":true'
  assert_contains "$output" '"matched_symbol":"apiClient.post"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "js.ast.call_match@v1" \
    --source-file "src/client.js" \
    --callee "delete"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "js.ast.call_match@v1" \
    --source-file "src/client.js" \
    --callee "fetch"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"matched_symbol":"fetch"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "js.ast.call_match@v1" \
    --source-file "src/client.js" \
    --callee "post" \
    --receiver "missingClient"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  cat > "$TEST_PROJECT/src/client.test.js" <<'EOF'
apiClient.post("/users");
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "js.ast.call_match@v1" \
    --source-file "src/client.test.js" \
    --callee "post" \
    --receiver "apiClient"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'
  assert_contains "$output" "primary validator"
}

@test "shadow_evidence_probe JavaScript parser-backed call matcher rejects nested excluded paths" {
  local excluded_dir
  mkdir -p "$TEST_PROJECT/src"

  for excluded_dir in node_modules dist build coverage test tests __tests__; do
    mkdir -p "$TEST_PROJECT/src/$excluded_dir"
    cat > "$TEST_PROJECT/src/$excluded_dir/client.js" <<'EOF'
apiClient.post("/users");
EOF

    run python3 "$SHADOW_PROBE" \
      --project-root "$TEST_PROJECT" \
      --validator-id "js.ast.call_match@v1" \
      --source-file "src/$excluded_dir/client.js" \
      --callee "post" \
      --receiver "apiClient"

    [ "$status" -eq 64 ]
    assert_contains "$output" '"status":"error"'
    assert_contains "$output" "excluded for primary validator"
  done
}

@test "shadow_evidence_probe JavaScript parser-backed call matcher rejects regex literal only matches" {
  mkdir -p "$TEST_PROJECT/src"
  cat > "$TEST_PROJECT/src/client.js" <<'EOF'
const pattern = /apiClient.post\(/;
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "js.ast.call_match@v1" \
    --source-file "src/client.js" \
    --callee "post" \
    --receiver "apiClient"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'
}

@test "shadow_evidence_probe JavaScript parser-backed call matcher supports optional chaining receiver calls" {
  mkdir -p "$TEST_PROJECT/src"
  cat > "$TEST_PROJECT/src/client.js" <<'EOF'
async function createUser(client) {
  return client?.post("/users");
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "js.ast.call_match@v1" \
    --source-file "src/client.js" \
    --callee "post" \
    --receiver "client"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"matched_symbol":"client.post"'
}

@test "shadow_evidence_probe TypeScript parser-backed call matcher rejects signatures and declaration files" {
  mkdir -p "$TEST_PROJECT/src"
  cat > "$TEST_PROJECT/src/service.ts" <<'EOF'
interface Client {
  post(path: string): Promise<void>;
}

class Service {
  post(path: string): void {}

  run(client: Client) {
    client.post("/users");
  }
}
EOF
  cat > "$TEST_PROJECT/src/types.d.ts" <<'EOF'
interface Client {
  post(path: string): Promise<void>;
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "ts.ast.call_match@v1" \
    --source-file "src/service.ts" \
    --callee "post" \
    --receiver "client"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"validator_kind":"ts_token_parser"'
  assert_contains "$output" '"matched_symbol":"client.post"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "ts.ast.call_match@v1" \
    --source-file "src/types.d.ts" \
    --callee "post"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'
  assert_contains "$output" "primary validator"
  assert_contains "$output" "extension is rejected"
}

@test "shadow_evidence_probe TypeScript parser-backed call matcher rejects nested excluded paths" {
  local excluded_dir
  mkdir -p "$TEST_PROJECT/src"

  for excluded_dir in node_modules dist build coverage test tests __tests__; do
    mkdir -p "$TEST_PROJECT/src/$excluded_dir"
    cat > "$TEST_PROJECT/src/$excluded_dir/client.ts" <<'EOF'
client.post("/users");
EOF

    run python3 "$SHADOW_PROBE" \
      --project-root "$TEST_PROJECT" \
      --validator-id "ts.ast.call_match@v1" \
      --source-file "src/$excluded_dir/client.ts" \
      --callee "post" \
      --receiver "client"

    [ "$status" -eq 64 ]
    assert_contains "$output" '"status":"error"'
    assert_contains "$output" "excluded for primary validator"
  done
}

@test "shadow_evidence_probe TypeScript parser-backed v2 matcher supports generic call syntax while v1 stays fail-closed" {
  mkdir -p "$TEST_PROJECT/src"
  cat > "$TEST_PROJECT/src/service.ts" <<'EOF'
async function createUser(client: Client) {
  return client.post<Result<User>>("/users");
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "ts.ast.call_match@v1" \
    --source-file "src/service.ts" \
    --callee "post" \
    --receiver "client"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"validator_result":"not_found"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "ts.ast.call_match@v2" \
    --source-file "src/service.ts" \
    --callee "post" \
    --receiver "client"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"validator_id":"ts.ast.call_match@v2"'
  assert_contains "$output" '"matched_symbol":"client.post"'
  assert_contains "$output" '"type_arguments":true'
}

@test "shadow_evidence_probe JS and TS parser-backed matchers reject cross-extension files" {
  mkdir -p "$TEST_PROJECT/src"
  cat > "$TEST_PROJECT/src/client.ts" <<'EOF'
client.post("/users");
EOF
  cat > "$TEST_PROJECT/src/client.tsx" <<'EOF'
client.post("/users");
EOF
  cat > "$TEST_PROJECT/src/client.js" <<'EOF'
client.post("/users");
EOF
  cat > "$TEST_PROJECT/src/client.jsx" <<'EOF'
client.post("/users");
EOF
  cat > "$TEST_PROJECT/src/types.d.ts" <<'EOF'
declare const client: { post(path: string): void };
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "js.ast.call_match@v1" \
    --source-file "src/client.jsx" \
    --callee "post" \
    --receiver "client"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"matched_symbol":"client.post"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "ts.ast.call_match@v1" \
    --source-file "src/client.tsx" \
    --callee "post" \
    --receiver "client"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"matched_symbol":"client.post"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "js.ast.call_match@v1" \
    --source-file "src/client.ts" \
    --callee "post" \
    --receiver "client"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "js.ast.call_match@v1" \
    --source-file "src/client.tsx" \
    --callee "post" \
    --receiver "client"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "ts.ast.call_match@v1" \
    --source-file "src/client.js" \
    --callee "post" \
    --receiver "client"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "ts.ast.call_match@v1" \
    --source-file "src/client.jsx" \
    --callee "post" \
    --receiver "client"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "ts.ast.call_match@v1" \
    --source-file "src/types.d.ts" \
    --callee "post" \
    --receiver "client"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'
}

@test "shadow_evidence_probe regex fallback ignores comments and strings" {
  mkdir -p "$TEST_PROJECT/src/main/java/example"
  cat > "$TEST_PROJECT/src/main/java/example/CommentOnly.java" <<'EOF'
package example;

class CommentOnly {
  void update() {
    // userRepository.save(user);
    String sample = "userRepository.save(user)";
  }
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --fallback-pattern-id "java.regex.repository_save_call@v1" \
    --source-file "src/main/java/example/CommentOnly.java"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
  assert_contains "$output" '"fallback_result":"not_found"'
}

@test "shadow_evidence_probe rejects fallback evidence from excluded paths" {
  mkdir -p "$TEST_PROJECT/src/test/java/example"
  cat > "$TEST_PROJECT/src/test/java/example/UserServiceTest.java" <<'EOF'
class UserServiceTest {
  void testSave() {
    userRepository.save(user);
  }
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --fallback-pattern-id "java.regex.repository_save_call@v1" \
    --source-file "src/test/java/example/UserServiceTest.java"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'
  assert_contains "$output" "outside allowed_paths" || assert_contains "$output" "excluded"
}

@test "shadow_evidence_probe rejects primary source_probe evidence from excluded paths" {
  mkdir -p "$TEST_PROJECT/src/test/java/example"
  cat > "$TEST_PROJECT/src/test/java/example/UserServiceTest.java" <<'EOF'
class UserServiceTest {
  void testSave() {
    userRepository.save(user);
  }
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "jpa.repository.save@v1" \
    --source-file "src/test/java/example/UserServiceTest.java"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'
  assert_contains "$output" '"validator_id":"jpa.repository.save@v1"'
  assert_contains "$output" "primary validator"
}

@test "shadow_evidence_probe runtime trace requires exact explicit event line" {
  mkdir -p "$TEST_PROJECT/logs"
  cat > "$TEST_PROJECT/logs/runtime.trace" <<'EOF'
event=user.update started
event=user.cache.evict userId=42
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "any.runtime.trace@v1" \
    --trace-file "logs/runtime.trace" \
    --trace-event "event=user.cache.evict userId=42"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"pass"'
  assert_contains "$output" '"probe_status":"pass"'
  assert_contains "$output" '"fact_status":"deterministic_evidence"'
  assert_contains "$output" '"evidence_type":"runtime_trace"'
  assert_contains "$output" '"artifact_hash":"sha256:'
  assert_contains "$output" '"trace_ref":"logs/runtime.trace:2"'
  refute_contains "$output" '"parser_identity"'
  refute_contains "$output" '"parser_content_hash"'

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "any.runtime.trace@v1" \
    --trace-file "logs/runtime.trace" \
    --trace-event "user.cache.evict"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"fail"'
}

@test "shadow_evidence_probe runtime trace rejects duplicate and dotted selected fields" {
  local runtime_json_event='{"event":"user.cache.evict","userId":42,"timestamp":"2026-05-02T00:00:00Z"}'

  mkdir -p "$TEST_PROJECT/logs"
  printf '%s\n' "$runtime_json_event" > "$TEST_PROJECT/logs/runtime-json.trace"

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "any.runtime.trace@v1" \
    --trace-file "logs/runtime-json.trace" \
    --trace-event "$runtime_json_event" \
    --hash-input-scope "selected_fields" \
    --selected-field "event" \
    --selected-field "event"

  [ "$status" -ne 0 ]
  assert_contains "$output" '"status":"error"'
  assert_contains "$output" '"validator_id":"any.runtime.trace@v1"'
  assert_contains "$output" "--selected-field must not contain duplicates"

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "any.runtime.trace@v1" \
    --trace-file "logs/runtime-json.trace" \
    --trace-event "$runtime_json_event" \
    --hash-input-scope "selected_fields" \
    --selected-field "payload.event"

  [ "$status" -ne 0 ]
  assert_contains "$output" '"status":"error"'
  assert_contains "$output" '"validator_id":"any.runtime.trace@v1"'
  assert_contains "$output" "selected_fields scope supports only top-level field names"
}

@test "shadow_evidence_probe rejects traversal and does not write shadow docs" {
  mkdir -p "$TEST_PROJECT/src"
  cat > "$TEST_PROJECT/src/app.py" <<'EOF'
def handler():
    save_user()
EOF
  find "$DOCS_ROOT/shadow" -type f | sort > "$TEST_WORKSPACE/shadow-before.txt"

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "py.ast.call_match@v1" \
    --source-file "src/app.py" \
    --callee "save_user"

  [ "$status" -eq 0 ]
  find "$DOCS_ROOT/shadow" -type f | sort > "$TEST_WORKSPACE/shadow-after.txt"
  run cmp "$TEST_WORKSPACE/shadow-before.txt" "$TEST_WORKSPACE/shadow-after.txt"
  [ "$status" -eq 0 ]

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "py.ast.call_match@v1" \
    --source-file "../outside.py" \
    --callee "save_user"

  [ "$status" -eq 64 ]
  assert_contains "$output" "traversal"
  assert_contains "$output" '"validator_id":"py.ast.call_match@v1"'
}

