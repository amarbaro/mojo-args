#!/usr/bin/env bash
# The gate: tests/cases/argv.txt through Python argparse (tools/oracle.py) and through
# CASES (the Mojo runner built from tests/cases.mojo), outputs identical.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${CASES:?FAIL setup: set CASES to the built case runner}"
mkdir -p .work
python3 -I tools/oracle.py tests/cases/argv.txt > .work/exp.txt
timeout 30 "$CASES" tests/cases/argv.txt > .work/got.txt || { echo "FAIL run: runner exited non-zero"; exit 1; }
diff .work/exp.txt .work/got.txt > .work/diff.txt || { echo "FAIL check: differs from argparse"; head -20 .work/diff.txt; exit 1; }
echo "cases: $(grep -c '^>' .work/exp.txt), usage errors: $(grep -c 'exit 2' .work/exp.txt)"
echo "PASS all"
