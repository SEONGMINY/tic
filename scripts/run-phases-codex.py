#!/usr/bin/env python3
"""
Compatibility shim for the Codex phase runner.
Use scripts/run-phases.py for the canonical entrypoint.

Usage: python3 run-phases-codex.py <task-dir>
Example: python3 run-phases-codex.py 0-mvp
"""

import importlib.util
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
BASE_SCRIPT = SCRIPT_DIR / "run-phases.py"

spec = importlib.util.spec_from_file_location("run_phases_base", BASE_SCRIPT)
if spec is None or spec.loader is None:
    print(f"ERROR: failed to load {BASE_SCRIPT}")
    sys.exit(1)

module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


if __name__ == "__main__":
    module.main()
