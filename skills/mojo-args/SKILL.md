---
name: mojo-args
description: "Parse command-line arguments in Mojo with the mojo-args library, which behaves like Python argparse: options, abbreviations, sub-commands, a remainder command, exact usage-error text. Use when Mojo code needs flags, sub-commands or a typed CLI."
---

# mojo-args

argparse for Mojo 1.2. Its output and error messages are checked line by line against
CPython 3.14's `argparse`.

## Install

`mojo run -I <repo>/src app.mojo`, or `mojo precompile <repo>/src/args -o args.mojoc`,
or copy `src/args/`.

## Use

```mojo
from args import ArgumentParser

def main() raises:
    var p = ArgumentParser("tool")
    p.add_argument("--count", type="int", default="1")
    p.add_argument("-v", "--verbose", action="store_true")
    p.add_argument("--room", choices=["gpu", "cpu"], default="gpu")
    p.add_argument("name")
    var ns = p.parse_args()      # process args; usage error: stderr + exit 2
    print(ns.get_int("count"), ns.get_bool("verbose"), ns.get_str("name"))
```

Sub-commands: `p.add_subparsers("command")`, then `var run = p.add_parser("run")` and
`run[].add_argument(...)`. The chosen name is `ns.get_str("command")`. A command to run
after the options: a positional `cmd` with `nargs="..."`, read with `ns.get_list("cmd")`.

## Rules

- **Declare once, parse many times.** Build the parser at start; `parse_args(list)` does not
  change it.
- **Defaults are text.** `default="0"` with `type="int"`, as argparse converts a string
  default. `default` is not a typed value.
- **Read with the matching getter.** `get_int` on a `str` raises. `get_list` is for `append`
  and `nargs="..."`, `get_bool` for `store_true`, `is_none` for an option with no default.
- **Tests use the list form.** `p.parse_args(["run", "--prio", "5"])` raises `Error` with
  argparse's text; assert on that text. Only `parse_args()` with no argument exits.
- **`"..."` keeps `--`.** `run -- python x.py` gives `["--", "python", "x.py"]`; drop the
  first element yourself. Options after the first remainder argument stay in the list.
- **Abbreviations are on.** `--prio` works for `--priority`; adding `--prior2` later makes
  `--prio` an `ambiguous option` error. Spell out options in scripts.
- **Declaration errors raise at declaration** (`unknown action`, `nargs ... not supported`).

## Not supported

`nargs` other than one value and `"..."`, `store_const`, `count`, type callables, mutually
exclusive groups, `@file` arguments. `--help` prints a plain usage and option list.
`int` is 64-bit. Choices compare the text as typed; `append` lists hold text.

## Check

`scripts/ci.sh` (Python 3.14 for the oracle). Details in `README.md`, `docs/api.md`,
`docs/design.md`.
