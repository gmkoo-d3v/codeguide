from __future__ import annotations

import sys
from pathlib import Path

script_dir = Path(sys.argv[1])
route = sys.argv[2]
sys.path.insert(0, str(script_dir))
from ai_model_registry import RegistryError, load_registry

try:
    registry = load_registry(script_dir.parent / "config" / "ai_model_registry.json")
except RegistryError:
    raise SystemExit(1)

if route not in registry["models"] or ":" not in route:
    raise SystemExit(1)
