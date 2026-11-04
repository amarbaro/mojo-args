from args import ArgumentParser


def main() raises:
    var p = ArgumentParser("gpu-wait")
    p.add_subparsers("command")
    var run = p.add_parser("run")
    run[].add_argument("--priority", type="int", default="0")
    run[].add_argument("-q", "--quiet", action="store_true")
    run[].add_argument("cmd", nargs="...")

    var ns = p.parse_args(["run", "--prio", "90", "-q", "--", "python", "train.py"])
    print(ns.get_str("command"), ns.get_int("priority"), ns.get_bool("quiet"), " ".join(ns.get_list("cmd")))
