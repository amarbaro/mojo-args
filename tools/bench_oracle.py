"""Same work as tests/bench.mojo with Python argparse."""
import argparse, time

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

ROUNDS = 40000
t0 = time.perf_counter()
p = build()
t1 = time.perf_counter()
lines = [
    ["run", "--priority", "90", "--vram", "12.5", "--env", "A=1", "--env", "B=2", "-q", "--", "python", "train.py", "--seed", "1"],
    ["submit", "--prio=60", "--timeout=300", "--room", "cpu", "--", "sh", "-c", "echo hi"],
    ["run", "--pre", "--", "x"],
    ["cancel", "j42", "--force"],
    ["list", "-n", "5", "--all"],
]
total = 0
for _ in range(ROUNDS):
    for k, line in enumerate(lines):
        ns = p.parse_args(line)
        if k < 3:
            total += ns.priority + len(ns.cmd) + len(ns.env)
        elif k == 3:
            total += len(ns.id)
        else:
            total += ns.n
t2 = time.perf_counter()
print("build_us", int((t1 - t0) * 1e6), "parse_ms", int((t2 - t1) * 1000), "check", total)
