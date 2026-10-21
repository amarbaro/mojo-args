#!/usr/bin/env bash
# CI entry point, same on a GitHub runner and a local Ubuntu VM: install, build the case runner, the gate.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v uv >/dev/null || { echo "FAIL setup: uv not installed"; exit 1; }
uv sync || { echo "FAIL setup: uv sync"; exit 1; }
# the oracle is CPython 3.14's argparse: its usage-error text and "--" rules changed between releases
uv python install 3.14 || { echo "FAIL setup: python 3.14"; exit 1; }
export PATH="$(dirname "$(uv python find 3.14)"):$PATH"
python3 -c 'import sys; print("oracle argparse, python", sys.version.split()[0])'
mkdir -p .work
.venv/bin/mojo build -I src tests/cases.mojo -o .work/cases || { echo "FAIL build: tests/cases.mojo"; exit 1; }
CASES=.work/cases scripts/check.sh
