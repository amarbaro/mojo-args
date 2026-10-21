# API

```mojo
from args import ArgumentParser, Namespace
```

Every behaviour below is asserted in `tests/api.mojo`, or compared with Python `argparse`
in `tests/cases/argv.txt`. Usage errors are `Error` values whose text is argparse's message
without the `prog: error:` prefix.

## `ArgumentParser`

`ArgumentParser(prog, add_help=True)` makes a parser. With `add_help` it knows `-h` and
`--help`; without, `-h` is an ordinary unknown option.

### Declare

| Method | Does |
|---|---|
| `add_argument(*names, action, type, default, choices, nargs, dest, help, required)` | an option when the first name starts with `-`, else a positional |
| `add_subparsers(dest, required=True)` | the sub-command positional; its value is stored under `dest` |
| `add_parser(name) -> ArcPointer[ArgumentParser]` | a sub-command; its `prog` is `"<parent> <name>"`; call `add_argument` through `p[]` |

`add_argument` arguments:

| | Values |
|---|---|
| `action` | `"store"` (default), `"store_true"`, `"append"` |
| `type` | `"str"` (default), `"int"`, `"float"` |
| `default` | the text of the default, converted with `type`; a `store_true` defaults to `False`, an `append` to `[]`, anything else to None |
| `choices` | a `List[String]`; the typed text must be one of them |
| `nargs` | `""` (one value, default) or `"..."` (all that remains, a positional only) |
| `dest` | the name in the `Namespace`; default: the first `--long` option without dashes and with `_` for `-`, else the first option; for a positional, its name |
| `required` | an option that must appear; positionals (not `"..."`) always are |

A mistake in a declaration (`unknown action`, `unknown type`, `nargs ... not supported`,
no name) raises when declared.

### Parse

| Method | Does |
|---|---|
| `parse_args() -> Namespace` | parse the process arguments; on a usage error print usage and `prog: error: <message>` to stderr and exit with status 2 |
| `parse_args(args: List[String]) -> Namespace` | parse a list (no program name); raises `Error` on a usage error, including `unrecognized arguments: ...` |
| `parse_known(args, mut ns, mut extras)` | parse into `ns`; arguments it does not recognize are appended to `extras` |
| `usage() -> String` | `usage: prog [-h] [--opt OPT] ... name` |
| `format_help() -> String` | the usage line and the options with their `help` text |

What parsing does, as argparse does it:

- A unique prefix of a long option works (`--prio` for `--priority`); a prefix of several is
  `ambiguous option: --p could match --priority, --preemptible`.
- `--opt=value`, `--opt value`, `-n5`, `-n=5`, and bundled flags (`-qx`). A flag given a
  value is `ignored explicit argument '1'`.
- An option that needs a value and gets none (the end, `--`, or another option) is
  `argument --priority: expected one argument`. `--priority -3` takes `-3` as the value,
  unless some option string looks like a negative number.
- The last value of a repeated option wins; `append` collects them.
- `--` ends options. A positional drops it; a `"..."` positional keeps it.
- `"..."` takes everything from its first argument on, options included, so
  `run x --priority 3` leaves `--priority 3` in `cmd`.
- A sub-command name that is not declared is
  `argument command: invalid choice: 'bogus' (choose from 'submit', 'run')`. Arguments a
  sub-command does not know are reported by the top level as `unrecognized arguments: ...`.
- A missing required argument is `the following arguments are required: --name, src`.
- A value that does not convert is `argument --priority: invalid int value: 'high'`; one
  outside `choices` is `argument --room: invalid choice: 'tpu' (choose from 'gpu', 'cpu')`.
- The parser is not changed by parsing: parse as many times as you like.

## `Namespace`

One value per `dest`, set to its default before parsing, so every declared name is present.

| Method | Returns |
|---|---|
| `get_str(key)`, `get_int(key)`, `get_float(key)` | the value; raises `args: 'key' is not an int` on another kind, `args: no such key 'key'` on an unknown name |
| `get_bool(key)` | a `store_true` flag |
| `get_list(key)` | a `"..."` or `append` list, borrowed in place (no copy) |
| `is_none(key)` | True for an option or positional with no default that did not appear |
| `has(key)` | whether the name was declared |

`keys` and `vals` (`Value` with `kind` one of `V_NONE`, `V_STR`, `V_INT`, `V_FLOAT`,
`V_BOOL`, `V_LIST`) are public for code that prints or walks a namespace;
`tests/cases.mojo` does.
