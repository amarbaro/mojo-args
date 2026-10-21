# The real entry point: parse_args() reads the process arguments, prints usage and exits 2 on a mistake.
from args import ArgumentParser


def main() raises:
    var p = ArgumentParser("cli")
    p.add_argument("--count", type="int", default="1", help="how many times")
    p.add_argument("-v", "--verbose", action="store_true")
    p.add_argument("name")
    var ns = p.parse_args()
    for _ in range(ns.get_int("count")):
        print("hello", ns.get_str("name"))
