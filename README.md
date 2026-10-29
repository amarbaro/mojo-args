# mojo-args

[![CI](https://github.com/amarbaro/mojo-args/actions/workflows/ci.yml/badge.svg)](https://github.com/amarbaro/mojo-args/actions/workflows/ci.yml)

Command-line parsing for Mojo that behaves like Python's `argparse`: prefix abbreviation,
`--opt=value`, `-n5`, bundled flags, `--` handling, sub-commands, a remainder command, and
argparse's exact usage-error text. It parses 13× faster than argparse.

```mojo
from args import ArgumentParser

def main() raises:
    var p = ArgumentParser("gpu-wait")
    p.add_subparsers("command")
    var run = p.add_parser("run")
    run[].add_argument("--priority", type="int", default="0")
    run[].add_argument("--room", choices=["gpu", "cpu"], default="gpu")
    run[].add_argument("cmd", nargs="...")
    var ns = p.parse_args()          # the process arguments; usage error -> stderr, exit 2
    print(ns.get_str("command"), ns.get_int("priority"), ns.get_str("room"))
```

`gpu-wait run --prio 90 -- python train.py` gives `run 90 gpu`, and `cmd` is
`["--", "python", "train.py"]`, as in argparse.

## Install

Requires Mojo 1.2. No other dependency.

| Way | Command |
|---|---|
| Source path | `mojo run -I path/to/mojo-args/src app.mojo` |
| Precompiled | `mojo precompile src/args -o args.mojoc`, then put it next to your code |
| Vendor | copy `src/args/` into your project |

## What you get

- `ArgumentParser(prog)`: `add_argument` for options (`"-q", "--quiet"`) and positionals,
  `add_subparsers` and `add_parser` (nestable), `parse_args()` for the process arguments,
  `parse_args(list)` and `parse_known(list, ns, extras)` for any list.
- Actions `store`, `store_true`, `append`; types `str`, `int`, `float`; `choices`, `default`,
  `dest`, `required`, `help`; `nargs="..."` (argparse's REMAINDER) on a positional.
- `Namespace`: `get_str`, `get_int`, `get_float`, `get_bool`, `get_list`, `is_none`, `has`.
- Errors carry argparse's own text, for example
  `argument --room: invalid choice: 'tpu' (choose from 'gpu', 'cpu')` and
  `ambiguous option: --p could match --priority, --preemptible`.

The API is in [docs/api.md](docs/api.md). The memory and speed design is in
[docs/design.md](docs/design.md).

## Performance

`tests/bench.mojo` against `tools/bench_oracle.py`: one gpu-wait parser (four sub-commands) and 200,000 parses of five valid command lines. Three runs each.

| | build the parser | 200,000 parses | peak RSS |
|---|---|---|---|
| Python `argparse` | 11.3 to 11.5 ms | 3,346 to 3,367 ms | 15.1 to 15.3 MB |
| mojo-args | 0.04 to 0.05 ms | 252 to 259 ms | 12.0 to 12.3 MB |

An empty Mojo program uses 11.4 MB, so the library adds under 1 MB.

## Limits

- The oracle is CPython 3.14's `argparse`. Usage-error text and `--` rules changed between
  Python releases, so another version can word a message differently.
- `--help` prints a simple usage and option list, not argparse's layout. It is not gated.
  A usage error prints the top-level usage and program name, also for a sub-command error
  (argparse prints the sub-command's).
- Not supported: `nargs` other than one value and `"..."`, `store_const`, `count`, type
  callables, mutually exclusive groups, `@file` arguments, `allow_abbrev=False`.
- `int` is 64-bit and ASCII digits only (`"1_000"` is accepted, as in Python; `"٣"` and
  values past 2^63 are not). `float` rejects underscore forms such as `"1_0.5"`.
- `choices` compare against the text as typed, and `append` lists hold the text.

## Check

```
scripts/ci.sh
```

It runs `uv sync`, builds `tests/cases.mojo`, then `scripts/check.sh`. CI runs the same
script on every push.

`tests/cases/argv.txt` holds 75 command lines (34 of them usage errors). Each runs through
Python `argparse` (`tools/oracle.py`) and through this library, and the printed namespaces
and error messages must be identical. Then `tests/api.mojo` covers getters, declaration
errors, reuse and nesting, `examples/quickstart.mojo` runs, and `examples/cli.mojo` runs as
a real process: output, exit status 2 with the message on stderr, and `--help`.

## For coding agents

[skills/mojo-args/SKILL.md](skills/mojo-args/SKILL.md) tells an agent how to use the library
and what to avoid.
