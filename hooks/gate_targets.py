#!/usr/bin/env python3
"""Find the formal-verification entry points a Bash command would run, for verifiability-gate.sh.

Reads the PreToolUse hook JSON on stdin and prints one line per entry point:
    OK<TAB><ledger root><TAB><Name><TAB><entry kind>
    BLOCK<TAB><reason>
The command is split on operators, newlines and shell keywords; env/timeout/nice/sudo/nix develop -c/
python3/bash -c prefixes are peeled off, cd/pushd/env -C/make -C/lake -d are followed, and $(…)/`…`
are parsed as commands of their own. A heredoc body is text, unless a shell reads it (bash <<EOF,
cat <<EOF | sh), then it is parsed too. An entry point hidden where it cannot be read (eval, xargs,
python3 -c) is a BLOCK, not a pass.
"""
import json
import os
import re
import shlex
import sys

LOOP = re.compile(r"loop-(outer|middle|inner)")
# an entry point as it would be run, not merely mentioned (git commit -m "... lake ..." is text)
RUNS_ENTRY = re.compile(r"(^|[\s;&|(`])(loop-(outer|middle|inner)\b|\S*(smt_oracle|trace_check)\.py\b|lake\b[^;&|]*\bbuild\b)")
OPS = {";", "&", "&&", "|", "||", "|&", "(", ")", ";;"}
RESERVED = {"if", "then", "do", "else", "elif", "while", "until", "!", "{", "}", "fi", "done"}
# prefixes that run the rest of the words as a command; value-taking options per prefix
WRAPPERS = {"export": (), "nice": ("-n", "--adjustment"), "command": (), "exec": ("-a",), "nohup": (),
            "builtin": (), "time": ("-f", "-o"), "stdbuf": ("-i", "-o", "-e"),
            "sudo": ("-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U"), "caffeinate": ("-t", "-w")}
SHELLS = ("bash", "sh", "zsh", "dash", "fish")
REDIRECTS = {">", ">>", "<", ">&", "<&", ">|", "<>"}
# rest: the rest of the opening line (kept); body: dropped unless a shell reads it
HEREDOC = re.compile(r"<<-?\s*(?P<q>['\"]?)(?P<tag>\w+)(?P=q)(?P<rest>[^\n]*)\n(?P<body>.*?)\n[ \t]*(?P=tag)[ \t]*(?=\n|$)", re.S)
FEEDS_SHELL = re.compile(r"(^|[\s|;&(])(bash|sh|zsh|dash|fish)\b")
FEEDS_PYTHON = re.compile(r"(^|[\s|;&(])python3?(\.\d+)?\b")


def root_of(path, cwd):
    m = re.match(r"(.*?)/tasks/(loopeng|fv|verifiability)(/|$)", path)
    return m.group(1) if m else cwd


def substitutions(text):
    """Bodies of $(…) and `…`, outermost first. Single quotes keep them literal; inside double quotes a
    ' is a plain character and \\ escapes $ ` " \\ as in bash.
    shortcut: no quoting model inside $(…) itself (a ) in a string there can fool the depth count)."""
    out, i, dq = [], 0, False
    while i < len(text):
        if text[i] == "\\":
            i += 2
        elif text[i] == '"':
            dq, i = not dq, i + 1
        elif text[i] == "'" and not dq:
            j = text.find("'", i + 1)
            i = len(text) if j < 0 else j + 1
        elif text.startswith("$(", i):
            depth, j = 1, i + 2
            while j < len(text) and depth:
                depth += {"(": 1, ")": -1}.get(text[j], 0)
                j += 1
            out.append((i, j, text[i + 2:j - 1]))
            i = j
        elif text[i] == "`":
            j = text.find("`", i + 1)
            if j < 0:
                break
            out.append((i, j + 1, text[i + 1:j]))
            i = j + 1
        else:
            i += 1
    return out


class Gate:
    def __init__(self):
        self.lines = []

    def ok(self, root, name, entry="other"):
        if re.fullmatch(r"[A-Za-z0-9_]+", name):
            self.lines.append(f"OK\t{root}\t{name}\t{entry}")
        elif "$" in name:
            self.block(f"名前 {name!r} は変数で、実行前には決まらない。名前を直接書く")
        else:
            self.block(f"名前 {name!r} に使えない文字がある(英数字と _ だけにする)")

    def block(self, why):
        self.lines.append(f"BLOCK\t{why}")

    def segments(self, text):
        lex = shlex.shlex(text.replace("\n", " ; "), posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        seg = []
        try:
            for tok in lex:
                if tok in OPS:
                    if seg:
                        yield seg
                    seg = []
                else:
                    seg.append(tok)
        except ValueError:
            if RUNS_ENTRY.search(text):
                self.block("コマンドのクォートを読めない")
            return
        if seg:
            yield seg

    @staticmethod
    def skip_opts(toks, with_value=()):
        while toks and toks[0].startswith("-") and toks[0] != "-":
            opt, toks = toks[0], toks[1:]
            if opt in with_value and toks:
                toks = toks[1:]
        return toks

    def parse(self, text, cwd, env, depth=0):
        """env: variables exported so far in this command (SPEC= reaches make through the environment)."""
        def heredoc(m):
            opening = text[text.rfind("\n", 0, m.start()) + 1:m.start()] + m.group("rest")
            body = m.group("body")
            if FEEDS_SHELL.search(opening) and depth < 4:
                self.parse(body, cwd, dict(env), depth + 1)
            elif FEEDS_PYTHON.search(opening) and (RUNS_ENTRY.search(body) or LOOP.search(body)):
                self.block("python に流した heredoc の中の検証の入口は読めない。入口のコマンドを直接実行する")
            elif not m.group("q") and depth < 4:  # an unquoted heredoc still expands $(…) and `…`
                for _, _, sub in substitutions(body):
                    self.parse(sub, cwd, dict(env), depth + 1)
            return m.group("rest")
        text = HEREDOC.sub(heredoc, text)
        if depth < 4:
            # parse each substitution on its own (a cd inside it stays inside), then blank it out
            for start, end, body in reversed(substitutions(text)):
                self.parse(body, cwd, dict(env), depth + 1)
                text = text[:start] + "SUBST" + text[end:]
        for toks in self.segments(text):
            raw = " ".join(toks)
            local = {}
            while toks:
                t, base = toks[0], os.path.basename(toks[0])
                if t.isdigit() and toks[1:2] and toks[1] in REDIRECTS:
                    toks = toks[1:]
                elif t in REDIRECTS:
                    toks = toks[2:]
                elif re.match(r"^[A-Za-z_]\w*=", t):
                    k, v = t.split("=", 1)
                    local[k] = v
                    toks = toks[1:]
                elif t in RESERVED:
                    toks = toks[1:]
                elif t in WRAPPERS:
                    if t == "export":
                        for a in toks[1:]:
                            if "=" in a and not a.startswith("-"):
                                k, v = a.split("=", 1)
                                env[k] = v
                        toks = []
                    else:
                        toks = self.skip_opts(toks[1:], WRAPPERS[t])
                elif t == "env":
                    toks = toks[1:]
                    while toks and (toks[0].startswith("-") or "=" in toks[0]):
                        opt, toks = toks[0], toks[1:]
                        if "=" in opt and not opt.startswith("-"):
                            k, v = opt.split("=", 1)
                            local[k] = v
                        elif opt in ("-C", "--chdir") and toks:
                            cwd, toks = os.path.normpath(os.path.join(cwd, toks[0])), toks[1:]
                        elif opt in ("-u", "--unset", "-S") and toks:
                            toks = toks[1:]
                elif t == "timeout":
                    toks = self.skip_opts(toks[1:], ("-k", "--kill-after", "-s", "--signal"))[1:]
                elif t == "nix" and ("-c" in toks or "--command" in toks):
                    i = min(toks.index(x) for x in ("-c", "--command") if x in toks)
                    toks = toks[i + 1:]
                elif re.match(r"^python3?(\.\d+)?$", base):
                    rest, toks, inline = toks[1:], [], False
                    while rest and rest[0].startswith("-") and rest[0] != "-":
                        opt, rest = rest[0], rest[1:]
                        if opt == "-c":
                            if RUNS_ENTRY.search(" ".join(rest[:1])) or LOOP.search(" ".join(rest[:1])):
                                self.block("python3 -c の中から検証の入口を呼んでいる。入口のコマンドを直接実行する")
                            rest, inline = [], True
                            break
                        if opt in ("-W", "-X", "-m") and rest:
                            rest = rest[1:]
                    # python reading its stdin (… | python3, python3 -): the script is not visible here
                    if not inline and rest[:1] in ([], ["-"]) and re.search(r"\|\s*\S*python3?(\.\d+)?\b", text) \
                            and (RUNS_ENTRY.search(text) or LOOP.search(text)):
                        self.block("python の標準入力に流した検証の入口は読めない。入口のコマンドを直接実行する")
                    toks = rest
                elif base in SHELLS:
                    rest = toks[1:]
                    while rest and rest[0].startswith("-") and not re.fullmatch(r"-\w*c\w*", rest[0]):
                        # -o NAME / -euo NAME / +O NAME take a value
                        rest = rest[2:] if re.fullmatch(r"[-+]\w*[oO]", rest[0]) else rest[1:]
                    if rest and re.fullmatch(r"-\w*c\w*", rest[0]) and len(rest) > 1 and depth < 4:
                        self.parse(rest[1], cwd, {**env, **local}, depth + 1)
                    elif "<<<" in rest and rest.index("<<<") + 1 < len(rest) and depth < 4:
                        self.parse(rest[rest.index("<<<") + 1], cwd, {**env, **local}, depth + 1)
                    elif not [a for a in rest if a not in ("-", "-s")] and (RUNS_ENTRY.search(text) or LOOP.search(text)):
                        # a shell reading its stdin (echo … | bash): the script is not visible here
                        self.block(f"{base} の標準入力に流した検証の入口は読めない。入口のコマンドを直接実行する")
                    toks = []
                elif base in ("eval", "xargs", "parallel", "watch"):
                    if RUNS_ENTRY.search(raw) or LOOP.search(raw):
                        self.block(f"{base} の中の検証の入口は読めない。入口のコマンドを直接実行する")
                    toks = []
                else:
                    break
            if not toks:
                continue
            self.entry(os.path.basename(toks[0]), toks[1:], cwd, {**env, **local})
            if os.path.basename(toks[0]) in ("cd", "pushd"):
                target = next((a for a in toks[1:] if not a.startswith("-")), "~")
                cwd = os.path.normpath(os.path.join(cwd, os.path.expanduser(target)))

    def entry(self, verb, args, cwd, env):
        if verb in ("loop-outer", "loop-middle", "loop-inner") or (
                verb == "make" and any(LOOP.fullmatch(a) for a in args)):
            here = cwd
            for i, a in enumerate(args if verb == "make" else []):
                d = args[i + 1] if a in ("-C", "--directory") and i + 1 < len(args) else (
                    a[2:] if a.startswith("-C") and len(a) > 2 else a.split("=", 1)[1] if a.startswith("--directory=") else None)
                if d:
                    here = os.path.normpath(os.path.join(here, d))
            specs = [m.group(1) for a in args for m in [re.fullmatch(r"SPEC=(.*)", a)] if m]
            if not specs:
                specs = [env.get("SPEC", "Spec")]  # Makefile.loopeng: SPEC ?= Spec
            for name in specs:
                self.ok(root_of(here, here), name)
        elif verb in ("smt_oracle.py", "trace_check.py"):
            rest = self.skip_opts(args, ("--cfg", "--timeout"))
            while rest:  # options may also follow the positional arguments
                if not rest[0].startswith("-"):
                    path = os.path.normpath(os.path.join(cwd, rest[0]))
                    self.ok(root_of(path, cwd), re.sub(r"(\.smt)?\.py$|\.tla$", "", os.path.basename(path)),
                            "trace_check" if verb == "trace_check.py" else "other")
                    break
                rest = self.skip_opts(rest, ("--cfg", "--timeout"))
        elif verb == "lake" and "build" in args:
            if "$" in cwd:
                self.block("変数を含む cd の先は決まらないので、lake build の台帳を特定できない。パスを直接書く")
                return
            here = cwd
            for i, a in enumerate(args):
                d = args[i + 1] if a in ("-d", "--dir") and i + 1 < len(args) else (
                    a.split("=", 1)[1] if a.startswith("--dir=") else None)
                if d:
                    here = os.path.normpath(os.path.join(cwd, d))
            m = re.match(r"(.*)/tasks/fv/([^/]+)", here)
            if m:
                self.ok(m.group(1), m.group(2))


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    gate = Gate()
    gate.parse(payload.get("tool_input", {}).get("command", ""), payload.get("cwd") or os.getcwd(), {})
    print("\n".join(gate.lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
