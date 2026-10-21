# Behaviour a declared parser must have beyond the argparse cases: getters, dest rules,
# declaration errors, reuse, required options, parse_known, usage text.
from std.testing import assert_equal, assert_true, assert_false, assert_raises
from args import ArgumentParser, Namespace


def build() raises -> ArgumentParser:
    var p = ArgumentParser("tool")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("-j", "--jobs", type="int", default="4", dest="workers")
    p.add_argument("--ratio", type="float", default="0.5")
    p.add_argument("--tag", action="append")
    p.add_argument("--name", required=True)
    p.add_argument("src")
    p.add_argument("rest", nargs="...")
    return p^


def msg(p: ArgumentParser, args: List[String]) -> String:
    try:
        _ = p.parse_args(args)
    except e:
        return String(e)
    return "no error"


def main() raises:
    var p = build()

    # typed getters, dest derived from the long option, dest= overrides
    var ns = p.parse_args(["--name", "n", "--dry-run", "-j8", "--ratio=2.5", "--tag", "a", "--tag", "b", "s", "x", "--y"])
    assert_true(ns.get_bool("dry_run"))
    assert_equal(ns.get_int("workers"), 8)
    assert_equal(ns.get_float("ratio"), 2.5)
    assert_equal(ns.get_str("name"), "n")
    assert_equal(ns.get_str("src"), "s")
    assert_equal(ns.get_list("tag"), ["a", "b"])
    assert_equal(ns.get_list("rest"), ["x", "--y"])
    assert_false(ns.has("jobs"))

    # defaults, and a second parse does not see the first one's appends
    var d = p.parse_args(["--name", "n", "s"])
    assert_false(d.get_bool("dry_run"))
    assert_equal(d.get_int("workers"), 4)
    assert_equal(d.get_float("ratio"), 0.5)
    assert_equal(len(d.get_list("tag")), 0)
    assert_equal(len(d.get_list("rest")), 0)
    assert_equal(len(ns.get_list("tag")), 2)

    # getters are strict
    assert_true(ns.has("name"))
    with assert_raises(contains="no such key"):
        _ = ns.get_int("nope")
    with assert_raises(contains="'name' is not an int"):
        _ = ns.get_int("name")
    var opt = ArgumentParser("o")
    opt.add_argument("--label")
    assert_true(opt.parse_args(List[String]()).is_none("label"))

    # usage errors carry argparse's text
    assert_equal(msg(p, ["s"]), "the following arguments are required: --name")
    assert_equal(msg(p, ["--name", "n"]), "the following arguments are required: src")
    assert_equal(msg(p, List[String]()), "the following arguments are required: --name, src")
    assert_equal(msg(p, ["--name", "n", "--jobs", "x", "s"]), "argument -j/--jobs: invalid int value: 'x'")
    assert_equal(msg(p, ["--name", "n", "--ratio", "x", "s"]), "argument --ratio: invalid float value: 'x'")
    assert_equal(msg(p, ["--name", "n", "--dry-run=1", "s"]), "argument --dry-run: ignored explicit argument '1'")

    # abbreviation: a unique prefix works, a shared one is an error naming every match
    p.add_argument("--nick")
    assert_equal(p.parse_args(["--name", "n", "--ni", "k", "s"]).get_str("nick"), "k")
    assert_equal(msg(p, ["--n", "n", "s"]), "ambiguous option: --n could match --name, --nick")

    # last value wins, "--" ends options and is dropped before a positional, kept in a remainder
    assert_equal(p.parse_args(["--name", "n", "-j", "3", "-j", "5", "s"]).get_int("workers"), 5)
    var dd = p.parse_args(["--name", "n", "--", "s", "-j"])
    assert_equal(dd.get_str("src"), "s")
    assert_equal(dd.get_list("rest"), ["-j"])
    var rem = p.parse_args(["--name", "n", "s", "--name", "m"])
    assert_equal(rem.get_str("name"), "n")
    assert_equal(rem.get_list("rest"), ["--name", "m"])

    # parse_known returns what it does not recognize instead of raising
    var q = ArgumentParser("q")
    q.add_argument("-v", action="store_true")
    var kn = Namespace()
    var extras = List[String]()
    q.parse_known(["-v", "--zzz", "a"], kn, extras)
    assert_true(kn.get_bool("v"))
    assert_equal(extras, ["--zzz", "a"])
    assert_equal(msg(q, ["--zzz", "a"]), "unrecognized arguments: --zzz a")

    # sub-commands: prog, required, and a sub-command's own errors
    var t = ArgumentParser("t")
    t.add_subparsers("cmd")
    var go = t.add_parser("go")
    go[].add_argument("n", type="int")
    assert_equal(go[].prog, "t go")
    assert_equal(t.parse_args(["go", "3"]).get_int("n"), 3)
    assert_equal(t.parse_args(["go", "3"]).get_str("cmd"), "go")
    assert_equal(msg(t, List[String]()), "the following arguments are required: cmd")
    assert_equal(msg(t, ["go"]), "the following arguments are required: n")
    assert_equal(msg(t, ["go", "x"]), "argument n: invalid int value: 'x'")
    assert_equal(msg(t, ["stop"]), "argument cmd: invalid choice: 'stop' (choose from 'go')")

    # sub-commands nest
    var nest = ArgumentParser("t")
    nest.add_subparsers("cmd")
    var g = nest.add_parser("go")
    g[].add_subparsers("sub")
    g[].add_parser("fast")[].add_argument("-n", type="int", default="1")
    var fast = nest.parse_args(["go", "fast", "-n", "3"])
    assert_equal(fast.get_str("sub"), "fast")
    assert_equal(fast.get_int("n"), 3)
    assert_equal(msg(nest, ["go"]), "the following arguments are required: sub")
    assert_equal(msg(nest, ["go", "slow"]), "argument sub: invalid choice: 'slow' (choose from 'fast')")
    assert_equal(msg(nest, ["go", "fast", "-x"]), "unrecognized arguments: -x")

    # usage line
    assert_equal(
        p.usage(),
        "usage: tool [-h] [--dry-run] [-j WORKERS] [--ratio RATIO] [--tag TAG] --name NAME [--nick NICK] src ...",
    )

    # declaration mistakes fail at declaration
    with assert_raises(contains="unknown action"):
        opt.add_argument("--x", action="count")
    with assert_raises(contains="unknown type"):
        opt.add_argument("--x", type="complex")
    with assert_raises(contains="not supported"):
        opt.add_argument("pos", nargs="+")
    with assert_raises(contains="needs a name"):
        opt.add_argument()
    with assert_raises(contains="positionals only"):
        opt.add_argument("--x", nargs="...")

    # an option that looks like a negative number turns "-5" from a value into an option
    var neg = ArgumentParser("neg")
    neg.add_argument("n")
    assert_equal(neg.parse_args(["-5"]).get_str("n"), "-5")
    neg.add_argument("-1", action="store_true")
    assert_equal(msg(neg, ["-5"]), "the following arguments are required: n")

    # no -h unless asked for: "-h" is then an ordinary unknown option
    assert_equal(msg(ArgumentParser("n", add_help=False), ["-h"]), "unrecognized arguments: -h")
