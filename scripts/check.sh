#!/usr/bin/env bash
# The gate: tests/cases/argv.txt through Python argparse (tools/oracle.py) and through
# CASES (the Mojo runner built from tests/cases.mojo), outputs identical; then the API test
# and the quickstart example.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${CASES:?FAIL setup: set CASES to the built case runner}"
mkdir -p .work
python3 -I tools/oracle.py tests/cases/argv.txt > .work/exp.txt
timeout 30 "$CASES" tests/cases/argv.txt > .work/got.txt || { echo "FAIL run: runner exited non-zero"; exit 1; }
diff .work/exp.txt .work/got.txt > .work/diff.txt || { echo "FAIL check: differs from argparse"; head -20 .work/diff.txt; exit 1; }
echo "cases: $(grep -c '^>' .work/exp.txt), usage errors: $(grep -c 'exit 2' .work/exp.txt)"
M=.venv/bin/mojo
$M run -I src tests/api.mojo || { echo "FAIL api: tests/api.mojo"; exit 1; }
$M run -I src examples/quickstart.mojo > /dev/null || { echo "FAIL example: examples/quickstart.mojo"; exit 1; }
# the process entry point: real argv, stdout, stderr and exit status
out=$($M run -I src examples/cli.mojo --count 2 bob 2>&1) || { echo "FAIL cli: valid argv exited non-zero"; exit 1; }
[[ "$out" == *$'hello bob\nhello bob' ]] || { echo "FAIL cli: wrong output: $out"; exit 1; }
rc=0; err=$($M run -I src examples/cli.mojo --count x bob 2>&1) || rc=$?
[[ $rc == 2 && "$err" == *"cli: error: argument --count: invalid int value: 'x'" ]] || { echo "FAIL cli: bad value gave rc $rc: $err"; exit 1; }
out=$($M run -I src examples/cli.mojo --help 2>&1) || { echo "FAIL cli: --help exited non-zero"; exit 1; }
[[ "$out" == *"usage: cli [-h] [--count COUNT] [-v] name"* ]] || { echo "FAIL cli: --help prints no usage"; exit 1; }
echo "PASS all"
