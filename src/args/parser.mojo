from std.collections import Optional
from std.memory import ArcPointer, bitcast
from std.sys import argv, exit, stderr

comptime STORE = 0
comptime TRUE = 1
comptime APPEND = 2
comptime REMAINDER = 3
comptime HELP = 4
comptime SUBCMD = 5
comptime T_STR = 0
comptime T_INT = 1
comptime T_FLOAT = 2
comptime V_NONE = 0
comptime V_STR = 1
comptime V_INT = 2
comptime V_FLOAT = 3
comptime V_BOOL = 4
comptime V_LIST = 5
comptime DASH: UInt8 = 45  # "--" in the argument pattern
comptime ARG: UInt8 = 65  # a plain argument
comptime OPT: UInt8 = 79  # something that looks like an option


def _repr(s: String) -> String:
    """Python repr() of a str."""
    var q = '"' if ("'" in s and '"' not in s) else "'"
    var out = q
    for c in s.codepoint_slices():
        var b = c.as_bytes()[0]
        if c == q or c == "\\":
            out += "\\" + String(c)
        elif c == "\n":
            out += "\\n"
        elif c == "\t":
            out += "\\t"
        elif c == "\r":
            out += "\\r"
        elif b < 32 or b == 127:
            comptime HEX = "0123456789abcdef"
            out += "\\x" + HEX[byte=Int(b >> 4)] + HEX[byte=Int(b & 15)]
        else:
            out += c
    return out + q


def _join_repr(xs: List[String]) -> String:
    var out = String()
    for i in range(len(xs)):
        out += ", " + _repr(xs[i]) if i > 0 else _repr(xs[i])
    return out^


@fieldwise_init
struct Value(Copyable):
    var s: String
    var l: List[String]
    var n: Int  # int, bool, or the bits of a float
    var kind: Int


def _val(kind: Int, n: Int = 0, s: String = "") -> Value:
    return Value(s, List[String](), n, kind)


struct Namespace(Movable):
    """The parsed values, keyed by dest, like argparse.Namespace."""

    var keys: List[String]
    var vals: List[Value]

    def __init__(out self):
        self.keys = List[String](capacity=16)
        self.vals = List[Value](capacity=16)

    def find(self, key: String) -> Int:
        for i in range(len(self.keys)):
            if self.keys[i] == key:
                return i
        return -1

    def set(mut self, key: String, var v: Value):
        var i = self.find(key)
        if i >= 0:
            self.vals[i] = v^
        else:
            self.keys.append(key)
            self.vals.append(v^)

    def _at(self, key: String, kind: Int, what: String) raises -> Int:
        var i = self.find(key)
        if i < 0:
            raise Error("args: no such key '" + key + "'")
        if self.vals[i].kind != kind:
            raise Error("args: '" + key + "' is not " + what)
        return i

    def has(self, key: String) -> Bool:
        return self.find(key) >= 0

    def is_none(self, key: String) raises -> Bool:
        var i = self.find(key)
        if i < 0:
            raise Error("args: no such key '" + key + "'")
        return self.vals[i].kind == V_NONE

    def get_str(self, key: String) raises -> String:
        return self.vals[self._at(key, V_STR, "a str")].s

    def get_int(self, key: String) raises -> Int:
        return self.vals[self._at(key, V_INT, "an int")].n

    def get_float(self, key: String) raises -> Float64:
        return bitcast[DType.float64](Int64(self.vals[self._at(key, V_FLOAT, "a float")].n))

    def get_bool(self, key: String) raises -> Bool:
        return self.vals[self._at(key, V_BOOL, "a bool")].n != 0

    def get_list(self, key: String) raises -> ref [self.vals[0].l] List[String]:
        """The list in place, no copy."""
        return self.vals[self._at(key, V_LIST, "a list")].l


@fieldwise_init
struct Arg(Copyable):
    var names: List[String]  # option strings; empty for a positional
    var choices: List[String]
    var dest: String
    var default: String
    var help: String
    var action: Int
    var type: Int
    var has_default: Bool
    var required: Bool

    def name(self) -> String:
        return "/".join(self.names) if len(self.names) > 0 else self.dest

    def takes_value(self) -> Bool:
        return self.action == STORE or self.action == APPEND


@fieldwise_init
struct _Match(Copyable):
    """One reading of an option-looking argument (argparse's option tuple)."""

    var opt: String
    var explicit: String
    var action: Int  # index into args; -1 = unknown option
    var has_explicit: Bool
    var sep: Bool  # the explicit part followed an "="


struct _Plan(Movable):
    """The classified argument list: read-only while parsing."""

    var pat: List[UInt8]
    var oi: List[Int]  # first _Match of an option argument, else -1
    var oc: List[Int]
    var om: List[_Match]

    def __init__(out self, n: Int):
        self.pat = List[UInt8](capacity=n)
        self.oi = List[Int](capacity=n)
        self.oc = List[Int](capacity=n)
        self.om = List[_Match]()


struct _State(Movable):
    var pos: List[Int]  # positionals still to fill
    var seen: List[Bool]
    var extras: List[String]
    var unrec: List[String]  # extras from sub-parsers

    def __init__(out self, args: List[Arg]):
        self.pos = List[Int](capacity=len(args))
        self.seen = List[Bool](length=len(args), fill=False)
        self.extras = List[String]()
        self.unrec = List[String]()
        for i in range(len(args)):
            if len(args[i].names) == 0:
                self.pos.append(i)


def _clen(b: UInt8) -> Int:
    return 1 if b < 0x80 else (2 if b < 0xE0 else (3 if b < 0xF0 else 4))


struct ArgumentParser(Movable):
    var prog: String
    var args: List[Arg]
    var onames: List[String]  # every option string, in declaration order
    var oact: List[Int]  # the arg of each option string
    var sub_names: List[String]
    var subs: List[ArcPointer[ArgumentParser]]
    var neg_opts: Bool  # an option string looks like a negative number

    def __init__(out self, prog: String, add_help: Bool = True):
        self.prog = prog
        self.args = List[Arg]()
        self.onames = List[String]()
        self.oact = List[Int]()
        self.sub_names = List[String]()
        self.subs = List[ArcPointer[ArgumentParser]]()
        self.neg_opts = False
        if add_help:
            self._add(Arg(["-h", "--help"], List[String](), "help", "", "show this help message and exit", HELP, T_STR, False, False))

    def _add(mut self, var a: Arg):
        for n in a.names:
            self.onames.append(n)
            self.oact.append(len(self.args))
            var b = n.as_bytes()
            if len(b) > 1 and b[1] >= 48 and b[1] <= 57:
                self.neg_opts = True
        self.args.append(a^)

    def add_argument(
        mut self,
        *names: String,
        action: String = "store",
        type: String = "str",
        default: Optional[String] = None,
        choices: List[String] = List[String](),
        nargs: String = "",
        dest: String = "",
        help: String = "",
        required: Bool = False,
    ) raises:
        """Declare an option ("-q", "--quiet") or a positional ("cmd")."""
        var a = Arg(List[String](), choices.copy(), dest, default.or_else(""), help, STORE, T_STR, Bool(default), required)
        for n in names:
            a.names.append(String(n))
        if action == "store_true":
            a.action = TRUE
        elif action == "append":
            a.action = APPEND
        elif action != "store":
            raise Error("args: unknown action '" + action + "'")
        if type == "int":
            a.type = T_INT
        elif type == "float":
            a.type = T_FLOAT
        elif type != "str":
            raise Error("args: unknown type '" + type + "'")
        if len(a.names) == 0:
            raise Error("args: add_argument needs a name")
        if a.names[0].as_bytes()[0] != 45:
            if len(a.names) != 1 or a.action != STORE:
                raise Error("args: a positional takes one name and action store")
            a.dest = a.names[0]
            a.names = List[String]()
            if nargs == "...":
                a.action = REMAINDER
            elif nargs != "":
                raise Error("args: nargs '" + nargs + "' is not supported")
            else:
                a.required = True
        else:
            if nargs != "":
                raise Error("args: nargs is for positionals only")
            if dest == "":
                var long = a.names[0]
                for n in a.names:
                    if n.startswith("--"):
                        long = n
                        break
                a.dest = String(long.lstrip("-")).replace("-", "_")
        self._add(a^)

    def add_subparsers(mut self, dest: String, required: Bool = True):
        """Declare the sub-command positional; add_parser fills it."""
        self._add(Arg(List[String](), List[String](), dest, "", "", SUBCMD, T_STR, False, required))

    def add_parser(mut self, name: String) -> ArcPointer[ArgumentParser]:
        self.sub_names.append(name)
        self.subs.append(ArcPointer(ArgumentParser(self.prog + " " + name)))
        return self.subs[len(self.subs) - 1]

    # ---- help ----

    def usage(self) -> String:
        var u = "usage: " + self.prog
        for a in self.args:
            if len(a.names) > 0:
                var item = a.names[0] if not a.takes_value() else a.names[0] + " " + a.dest.upper()
                u += " " + item if a.required else " [" + item + "]"
        for a in self.args:
            if len(a.names) == 0:
                u += (" {" + ",".join(self.sub_names) + "} ...") if a.action == SUBCMD else (" ..." if a.action == REMAINDER else " " + a.dest)
        return u^

    def format_help(self) -> String:
        var h = self.usage() + "\n\noptions:"
        for a in self.args:
            if len(a.names) > 0:
                h += "\n  " + ", ".join(a.names) + ((" " + a.dest.upper()) if a.takes_value() else "") + "  " + a.help
        return h^

    # ---- parsing ----

    def parse_args(self, args: Span[String, _]) raises -> Namespace:
        """Parse args (without the program name). Raises Error with argparse's usage-error text."""
        var ns = Namespace()
        var extras = List[String]()
        self.parse_known(args, ns, extras)
        if len(extras) > 0:
            raise Error("unrecognized arguments: " + " ".join(extras))
        return ns^

    def parse_args(self) raises -> Namespace:
        """Parse the process arguments, exiting with status 2 and a message on a usage error."""
        var l = List[String](capacity=len(argv()))
        for i in range(1, len(argv())):
            l.append(String(argv()[i]))
        try:
            return self.parse_args(l)
        except e:
            print(self.usage(), file=stderr)
            print(self.prog + ": error: " + String(e), file=stderr)
            exit(2)
        return Namespace()  # exit() does not return

    def _err(self, a: Int, msg: String) -> Error:
        return Error("argument " + self.args[a].name() + ": " + msg)

    def _convert(self, a: Int, s: String) raises -> Value:
        ref arg = self.args[a]
        try:
            if arg.type == T_INT:
                return _val(V_INT, Int(s))
            if arg.type == T_FLOAT:
                return _val(V_FLOAT, Int(bitcast[DType.int64](Float64(s))))
        except:
            raise self._err(a, "invalid " + ("int" if arg.type == T_INT else "float") + " value: " + _repr(s))
        return _val(V_STR, 0, s)

    def _find_opt(self, name: String) -> Int:
        for i in range(len(self.onames)):
            if self.onames[i] == name:
                return i
        return -1

    def _seed(self, mut ns: Namespace) raises:
        for i in range(len(self.args)):
            ref a = self.args[i]
            if a.action == TRUE:
                ns.set(a.dest, _val(V_BOOL, 0))
            elif a.action == APPEND:
                ns.set(a.dest, _val(V_LIST))
            elif a.action != HELP:
                ns.set(a.dest, self._convert(i, a.default) if a.has_default else _val(V_NONE))

    def _classify(self, s: String, mut om: List[_Match]) -> Int:
        """argparse's _parse_optional: how many readings of s as an option (0 = a plain argument)."""
        var b = s.as_bytes()
        if len(b) == 0 or b[0] != 45:
            return 0
        var i = self._find_opt(s)
        if i >= 0:
            om.append(_Match(s, "", self.oact[i], False, False))
            return 1
        if len(b) == 1:
            return 0
        var eq = s.find("=")
        var head = String(s[byte=:eq]) if eq >= 0 else s
        var tail = String(s[byte = eq + 1 :]) if eq >= 0 else String()
        if eq >= 0:
            i = self._find_opt(head)
            if i >= 0:
                om.append(_Match(head, tail, self.oact[i], True, True))
                return 1
        var n0 = len(om)
        for k in range(len(self.onames)):
            ref o = self.onames[k]
            if b[1] == 45:
                if o.startswith(head):
                    om.append(_Match(o, tail, self.oact[k], eq >= 0, eq >= 0))
            elif o == s[byte=:2]:
                om.append(_Match(o, String(s[byte=2:]), self.oact[k], True, False))
            elif o.startswith(head):
                om.append(_Match(o, tail, self.oact[k], eq >= 0, eq >= 0))
        if len(om) > n0:
            return len(om) - n0
        if (b[1] >= 48 and b[1] <= 57) or (len(b) > 2 and b[1] == 46 and b[2] >= 48 and b[2] <= 57):
            if not self.neg_opts:
                return 0
        if " " in s:
            return 0
        om.append(_Match(s, "", -1, False, False))
        return 1

    def parse_known(self, args: Span[String, _], mut ns: Namespace, mut extras: List[String]) raises:
        """Parse into ns; unrecognized arguments go to extras."""
        self._seed(ns)
        var n = len(args)
        var plan = _Plan(n)
        var maxo = -1
        var i = 0
        while i < n:
            if args[i] == "--":
                plan.pat.append(DASH)
                plan.oi.append(-1)
                plan.oc.append(0)
                i += 1
                while i < n:
                    plan.pat.append(ARG)
                    plan.oi.append(-1)
                    plan.oc.append(0)
                    i += 1
                break
            var c = self._classify(args[i], plan.om)
            plan.pat.append(OPT if c > 0 else ARG)
            plan.oi.append(len(plan.om) - c if c > 0 else -1)
            plan.oc.append(c)
            if c > 0:
                maxo = i
            i += 1
        var st = _State(self.args)
        var start = 0
        while start <= maxo:
            var nxt = start
            while nxt <= maxo and plan.oi[nxt] < 0:
                nxt += 1
            if start != nxt:
                var end = self._positionals(args, plan, st, ns, start)
                if end > start:
                    start = end
                    continue
            if plan.oi[start] < 0:
                for k in range(start, nxt):
                    st.extras.append(args[k])
                start = nxt
            start = self._optional(args, plan, st, ns, start)
        var stop = self._positionals(args, plan, st, ns, start)
        for k in range(stop, n):
            st.extras.append(args[k])
        var missing = List[String]()
        for k in range(len(self.args)):
            if self.args[k].required and not st.seen[k]:
                missing.append(self.args[k].name())
        if len(missing) > 0:
            raise Error("the following arguments are required: " + ", ".join(missing))
        extras.extend(st.extras.copy())
        extras.extend(st.unrec.copy())

    def _match(self, pos: List[Int], pat: List[UInt8], start: Int) -> List[Int]:
        """How many arguments each leading positional takes (argparse's _match_arguments_partial)."""
        var n = len(pat)
        for cnt in range(len(pos), 0, -1):
            var out = List[Int](capacity=cnt)
            var p = start
            for k in range(cnt):
                var act = self.args[pos[k]].action
                var q = p
                if act == REMAINDER:
                    q = n
                else:
                    while q < n and pat[q] == DASH:
                        q += 1
                    if q >= n or pat[q] != ARG:
                        break
                    q += 1
                    if act == SUBCMD:
                        q = n
                    else:
                        while q < n and pat[q] == DASH:
                            q += 1
                out.append(q - p)
                p = q
            if len(out) == cnt:
                return out^
        return List[Int]()

    def _positionals(self, args: Span[String, _], plan: _Plan, mut st: _State, mut ns: Namespace, start: Int) raises -> Int:
        var counts = self._match(st.pos, plan.pat, start)
        var s = start
        for k in range(len(counts)):
            var a = st.pos[k]
            var lo = s
            var hi = s + counts[k]
            var act = self.args[a].action
            if act == SUBCMD:
                lo += 1 if plan.pat[s] == DASH else 0
            elif act != REMAINDER:
                while plan.pat[lo] != ARG:
                    lo += 1
                hi = lo + 1
            self._take(a, args[lo:hi], st, ns)
            s += counts[k]
        for _ in range(len(counts)):
            _ = st.pos.pop(0)
        return s

    def _optional(self, args: Span[String, _], plan: _Plan, mut st: _State, mut ns: Namespace, start: Int) raises -> Int:
        var m0 = plan.oi[start]
        var cnt = plan.oc[start]
        if cnt > 1:
            var opts = String()
            for k in range(cnt):
                opts += (", " if k > 0 else "") + plan.om[m0 + k].opt
            raise Error("ambiguous option: " + args[start] + " could match " + opts)
        var a = plan.om[m0].action
        if a < 0:
            st.extras.append(args[start])
            return start + 1
        var opt = plan.om[m0].opt
        var expl = plan.om[m0].explicit
        var has = plan.om[m0].has_explicit
        var sep = plan.om[m0].sep
        var flags = List[Int]()  # earlier flags of a bundle like -qx
        var stop = start + 1
        var one = False  # the last action takes the explicit value
        var after = False  # the last action takes the arguments that follow
        while True:
            var val = self.args[a].takes_value()
            if has:
                if not val and opt.as_bytes()[1] != 45 and expl != "":
                    if sep or expl.as_bytes()[0] == 45:
                        raise self._err(a, "ignored explicit argument " + _repr(expl))
                    flags.append(a)
                    var cl = _clen(expl.as_bytes()[0])
                    var nxt = self._find_opt("-" + String(expl[byte=:cl]))
                    if nxt < 0:
                        st.extras.append("-" + expl)
                        break
                    a = self.oact[nxt]
                    opt = "-" + String(expl[byte=:cl])
                    var rest = String(expl[byte=cl:])
                    expl = rest^
                    has = expl != ""
                    sep = False
                    if has and expl.as_bytes()[0] == 61:
                        sep = True
                        var rest2 = String(expl[byte=1:])
                        expl = rest2^
                    continue
                if not val:
                    raise self._err(a, "ignored explicit argument " + _repr(expl))
                one = True
                break
            if val:
                if start + 1 >= len(plan.pat) or plan.pat[start + 1] != ARG:
                    raise self._err(a, "expected one argument")
                stop = start + 2
            after = True
            break
        for f in flags:
            self._take(f, args[0:0], st, ns)
        if one:
            st.seen[a] = True
            self._store(a, expl, ns)
        elif after:
            self._take(a, args[start + 1 : stop], st, ns)
        return stop

    def _store(self, a: Int, v: String, mut ns: Namespace) raises:
        ref arg = self.args[a]
        var val = self._convert(a, v)
        if len(arg.choices) > 0:
            var ok = False
            for c in arg.choices:
                ok = ok or c == v
            if not ok:
                raise self._err(a, "invalid choice: " + _repr(v) + " (choose from " + _join_repr(arg.choices) + ")")
        if arg.action == APPEND:
            ns.vals[ns.find(arg.dest)].l.append(v)
        else:
            ns.set(arg.dest, val^)

    def _take(self, a: Int, vals: Span[String, _], mut st: _State, mut ns: Namespace) raises:
        st.seen[a] = True
        ref arg = self.args[a]
        if arg.action == TRUE:
            ns.set(arg.dest, _val(V_BOOL, 1))
        elif arg.action == HELP:
            print(self.format_help())
            exit(0)
        elif arg.action == REMAINDER:
            var l = _val(V_LIST)
            for v in vals:
                l.l.append(v)
            ns.set(arg.dest, l^)
        elif arg.action == SUBCMD:
            var k = -1
            for j in range(len(self.sub_names)):
                if self.sub_names[j] == vals[0]:
                    k = j
            if k < 0:
                raise self._err(a, "invalid choice: " + _repr(vals[0]) + " (choose from " + _join_repr(self.sub_names) + ")")
            ns.set(arg.dest, _val(V_STR, 0, vals[0]))
            self.subs[k][].parse_known(vals[1:], ns, st.unrec)
        else:
            self._store(a, vals[0], ns)
