# Oracle runner: gpu-wait's parser (the same one tools/oracle.py builds), one argv per line of
# the cases file, namespace printed sorted and typed. scripts/check.sh diffs it with argparse.
from std.builtin.sort import sort
from std.sys import argv
from args import ArgumentParser, Namespace, V_NONE, V_STR, V_INT, V_FLOAT, V_BOOL


def shlex_split(line: String) -> List[String]:
    """Like shlex.split: whitespace, 'single', "double" quotes and backslash."""
    var out = List[String]()
    var cur = String()
    var has = False
    var q: UInt8 = 0
    var esc = False
    for c in line.codepoint_slices():
        var b = c.as_bytes()[0]
        if esc:
            cur += c
            esc = False
        elif q == 39:
            if b == 39:
                q = 0
            else:
                cur += c
        elif b == 92 and q != 39:
            esc = True
            has = True
        elif q == 34:
            if b == 34:
                q = 0
            else:
                cur += c
        elif b == 39 or b == 34:
            q = b
            has = True
        elif b == 32 or b == 9:
            if has or cur.byte_length() > 0:
                out.append(cur)
                cur = String()
                has = False
        else:
            cur += c
    if has or cur.byte_length() > 0:
        out.append(cur)
    return out^


def build() raises -> ArgumentParser:
    var p = ArgumentParser("gpu-wait")
    p.add_subparsers("command")
    for name in ["submit", "run"]:
        var s = p.add_parser(String(name))
        s[].add_argument("--room", choices=["gpu", "cpu"], default="gpu")
        s[].add_argument("--priority", type="int", default="0")
        s[].add_argument("--vram", type="float")
        s[].add_argument("--timeout", type="float")
        s[].add_argument("--env", action="append")
        s[].add_argument("--shared", action="store_true")
        s[].add_argument("--preemptible", action="store_true")
        s[].add_argument("--label")
        s[].add_argument("-q", "--quiet", action="store_true")
        s[].add_argument("cmd", nargs="...")
    var c = p.add_parser("cancel")
    c[].add_argument("id")
    c[].add_argument("--force", action="store_true")
    var l = p.add_parser("list")
    l[].add_argument("--all", action="store_true")
    l[].add_argument("-n", type="int", default="20")
    return p^


def show(ns: Namespace, i: Int) raises -> String:
    ref v = ns.vals[i]
    if v.kind == V_NONE:
        return "n"
    if v.kind == V_STR:
        return "s:" + v.s
    if v.kind == V_INT:
        return "i:" + String(v.n)
    if v.kind == V_FLOAT:
        return "f:" + String(ns.get_float(ns.keys[i]))
    if v.kind == V_BOOL:
        return "b:True" if v.n != 0 else "b:False"
    var out = String("l:[")
    for j in range(len(v.l)):
        out += ("," if j > 0 else "") + "s:" + v.l[j]
    return out + "]"


def main() raises:
    var p = build()
    for line in open(argv()[1], "r").read().split("\n"):
        if line.byte_length() == 0 or line.startswith("#"):
            continue
        print(">", line)
        try:
            var ns = p.parse_args(shlex_split(String(line)))
            var keys = ns.keys.copy()
            sort(keys)
            for k in keys:
                print(" ", k + "=" + show(ns, ns.find(k)))
            print("  exit 0")
        except e:
            print("  exit 2")
            print(" ", e)
