# 200,000 parses of five valid gpu-wait argv lists through one declared parser.
# Same work as tools/bench_oracle.py.
from std.time import perf_counter_ns
from args import ArgumentParser


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


def main() raises:
    comptime ROUNDS = 40000
    var t0 = perf_counter_ns()
    var p = build()
    var t1 = perf_counter_ns()
    var lines = List[List[String]]()
    lines.append(["run", "--priority", "90", "--vram", "12.5", "--env", "A=1", "--env", "B=2", "-q", "--", "python", "train.py", "--seed", "1"])
    lines.append(["submit", "--prio=60", "--timeout=300", "--room", "cpu", "--", "sh", "-c", "echo hi"])
    lines.append(["run", "--pre", "--", "x"])
    lines.append(["cancel", "j42", "--force"])
    lines.append(["list", "-n", "5", "--all"])
    var total = 0
    for _ in range(ROUNDS):
        for k in range(len(lines)):
            var ns = p.parse_args(lines[k])
            if k < 3:
                total += ns.get_int("priority") + len(ns.get_list("cmd")) + len(ns.get_list("env"))
            elif k == 3:
                total += ns.get_str("id").byte_length()
            else:
                total += ns.get_int("n")
    var t2 = perf_counter_ns()
    print("build_us", (t1 - t0) // 1000, "parse_ms", (t2 - t1) // 1000000, "check", total)
