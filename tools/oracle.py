"""Oracle: Python argparse on the argv lines of tests/cases/argv.txt.

The parser is gpu-wait's own shape (subcommands, typed and repeatable options, a
remainder command). For each argv line it prints the parsed namespace, sorted, typed:
  key=s:<str> | i:<int> | f:<repr> | b:True/False | l:[...] | n   then "exit 0"
or, for a usage error, "exit 2" and the first line of argparse's error message.
The Mojo side (tests/cases.mojo) declares the same parser and prints the same lines.
"""
import argparse, contextlib, io, shlex, sys

def build():
    p = argparse.ArgumentParser(prog="gpu-wait")
    sub = p.add_subparsers(dest="command", required=True)
    for name in ("submit", "run"):
        s = sub.add_parser(name)
        s.add_argument("--room", choices=["gpu", "cpu"], default="gpu")
        s.add_argument("--priority", type=int, default=0)
        s.add_argument("--vram", type=float, default=None)
        s.add_argument("--timeout", type=float, default=None)
        s.add_argument("--env", action="append", default=[])
        s.add_argument("--shared", action="store_true")
        s.add_argument("--preemptible", action="store_true")
        s.add_argument("--label", default=None)
        s.add_argument("-q", "--quiet", action="store_true")
        s.add_argument("cmd", nargs=argparse.REMAINDER)
    c = sub.add_parser("cancel"); c.add_argument("id"); c.add_argument("--force", action="store_true")
    l = sub.add_parser("list"); l.add_argument("--all", action="store_true"); l.add_argument("-n", type=int, default=20)
    return p

def show(v):
    if v is None: return "n"
    if isinstance(v, bool): return "b:%s" % v
    if isinstance(v, int): return "i:%d" % v
    if isinstance(v, float): return "f:%r" % v
    if isinstance(v, list): return "l:[" + ",".join(show(x) for x in v) + "]"
    return "s:" + v

for line in open(sys.argv[1]):
    line = line.rstrip("\n")
    if not line or line.startswith("#"): continue
    print(">", line)
    err = io.StringIO()
    try:
        with contextlib.redirect_stderr(err):
            ns = build().parse_args(shlex.split(line))
        for k in sorted(vars(ns)): print(" ", k + "=" + show(getattr(ns, k)))
        print("  exit 0")
    except SystemExit as e:
        msg = [x for x in err.getvalue().splitlines() if "error:" in x]
        print("  exit %d" % e.code); print("  " + (msg[0].split("error: ", 1)[1] if msg else ""))
