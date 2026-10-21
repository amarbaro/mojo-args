# A gpu-wait style CLI: sub-commands, typed options, a remainder command.
# parse_args() with no argument reads the process arguments; here a fixed argv shows the result.
from args import ArgumentParser


def main() raises:
    var p = ArgumentParser("gpu-wait")
    p.add_subparsers("command")
    var run = p.add_parser("run")
    run[].add_argument("--priority", type="int", default="0")
    run[].add_argument("--room", choices=["gpu", "cpu"], default="gpu")
    run[].add_argument("--env", action="append")
    run[].add_argument("-q", "--quiet", action="store_true")
    run[].add_argument("cmd", nargs="...")

    var ns = p.parse_args(["run", "--prio", "90", "--env", "A=1", "-q", "--", "python", "train.py"])
    print(ns.get_str("command"), ns.get_int("priority"), ns.get_str("room"), ns.get_bool("quiet"))
    print(ns.get_list("env")[0], " ".join(ns.get_list("cmd")))

    try:
        _ = p.parse_args(["run", "--room", "tpu"])
    except e:
        print(e)  # argument --room: invalid choice: 'tpu' (choose from 'gpu', 'cpu')
