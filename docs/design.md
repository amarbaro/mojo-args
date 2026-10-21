# Design

Two rules decide the layout: parse over the caller's strings without copying them, and do
what argparse does in the same order, so the messages come out the same.

## Same algorithm, no regular expressions

argparse turns the argument list into a string of `O` (looks like an option), `A` (plain
argument) and `-` (the `--` marker), then matches regular expressions of that string to
give each positional its arguments. `parse_known` builds the same pattern as a `List[UInt8]`
and walks it the same way: consume positionals, consume one option, repeat; unknown options
go to `extras`; required arguments are checked last.

The three positional shapes are `-*A-*` (one value), `.*` (the remainder) and `-*A[-AO]*`
(a sub-command and everything after it). A scan that takes `-` greedily gives the same
counts as the regex, because the pattern holds at most one `-`, so no backtracking is
needed. That is why the library has no regex dependency and no matcher object.

Abbreviation, bundling and `--opt=value` are argparse's `_get_option_tuples` and
`consume_optional`, ported branch for branch. A mistake there shows up as a differing line
in `tests/cases/argv.txt`, which is how the port was checked.

## Arguments are borrowed, values are copied once

`parse_args` takes a `Span[String]`: the caller's list is not copied, and a sub-command
parses `args[1:]`, which is another span over the same memory. The only copies are the
values stored in the `Namespace`. The classified pattern, the option readings
and the positional bookkeeping live in two small structs on the stack of `parse_known`
and are sized to the argument count up front.

`Namespace.get_list` returns the stored list in place. Copying it cost time in the
benchmark:

| | 200,000 parses plus getters |
|---|---|
| `get_list` returns a copy | 301 to 317 ms |
| `get_list` borrows | 252 to 259 ms |

Parsing alone, without reading any value, takes 241 to 245 ms.

## A value is 64 bytes

`Value` keeps a string, a list, one machine word and a kind. The word holds an int, a bool,
or the bits of a float, so there is no separate `Float64` field.

| layout | `size_of` |
|---|---|
| string, list, word, kind (used) | 64 B |
| kind, string, word, float, list | 72 B |

A `Namespace` is two lists sized for 16 entries at the start, so a typical command line does
not grow them.

## Lookups are scans

A parser has ten to twenty option strings. They sit in two parallel lists (`onames`,
`oact`) in declaration order, which is the order argparse reports ambiguous matches in, and
a lookup scans them. There is no `Dict`: it would hash every argument, and the order of
`ambiguous option: --p could match --priority, --preemptible` would need a second list.
`Namespace` finds a key the same way.

Building a parser is declaration only. The benchmark builds the four-command gpu-wait parser
in 43 to 54 us, where argparse takes 11.3 to 11.5 ms.

## Sub-commands nest through `ArcPointer`

A struct cannot hold a `List` of itself in Mojo 1.1 (`field 'kids' has non-'Deinitable'
type 'List[Node]'`). `add_parser` stores `ArcPointer[ArgumentParser]` and returns a copy of
the pointer, so `p.add_parser("run")[]` is the live sub-parser you keep declaring on.
The parse path only dereferences it, once per sub-command.

## What is left out

Only what the argparse cases need: one action per behaviour (`store`, `store_true`,
`append`), three types, one nargs form beyond a single value. The rest of argparse's
surface is in README "Limits".
