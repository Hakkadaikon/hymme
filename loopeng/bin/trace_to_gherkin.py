#!/usr/bin/env python3
"""Inner-loop glue: turn a TLA+ counterexample trace into a Gherkin scenario.

When TLC finds an invariant violation it prints the error trace as a sequence of
numbered states ("State 1:", "State 2: <Action ...>", each followed by
`var = value` lines). This is exactly an executable example: the initial state is
the Given, each action is a When, and the variables that changed are the Then.
We emit one Gherkin Scenario per trace so the design-level bug becomes a failing
acceptance test that the implementation must then satisfy.

Usage:
    tlc ... | trace_to_gherkin.py            # read TLC output from stdin
    trace_to_gherkin.py tlc_output.txt       # or from a file

ponytail: line-oriented parse of TLC's text trace, no TLA value parser. Handles
the flat `name = value` form TLC prints; nested records pass through verbatim.
"""
import re
import sys

STATE_RE = re.compile(r"^State (\d+):(?:\s*<([^>]*)>)?")
# TLC prints state vars either flat (`x = 1`) or as conjuncts (`/\ x = 1`); accept both.
ASSIGN_RE = re.compile(r"^(?:/\\\s*)?([A-Za-z_]\w*)\s*=\s*(.+)$")


def parse_states(text):
    """Return [(action, {var: value})] in trace order."""
    states, cur = [], None
    for line in text.splitlines():
        m = STATE_RE.match(line.strip())
        if m:
            if cur is not None:
                states.append(cur)
            action = (m.group(2) or "").strip()
            # action looks like "Next line 42, col ..." or "ActionName(...)" -- keep the head
            action = action.split(" line ")[0].strip() or "Init"
            cur = (action, {})
            continue
        if cur is not None:
            a = ASSIGN_RE.match(line.strip())
            if a:
                cur[1][a.group(1)] = a.group(2).strip()
    if cur is not None:
        states.append(cur)
    return states


def to_gherkin(states, name="Counterexample trace"):
    if not states:
        return None
    lines = ["Feature: design counterexample (auto-generated from TLC trace)",
             "", f"  Scenario: {name}"]
    init_action, init_vars = states[0]
    if init_vars:
        first = True
        for k, v in init_vars.items():
            kw = "Given" if first else "And"
            lines.append(f"    {kw} {k} = {v}")
            first = False
    prev = init_vars
    for action, vars_ in states[1:]:
        lines.append(f"    When {action}")
        changed = {k: v for k, v in vars_.items() if prev.get(k) != v}
        if not changed:
            lines.append("    Then the state is unchanged")
        else:
            first = True
            for k, v in changed.items():
                kw = "Then" if first else "And"
                lines.append(f"    {kw} {k} becomes {v}")
                first = False
        prev = vars_
    return "\n".join(lines) + "\n"


def main():
    text = open(sys.argv[1]).read() if len(sys.argv) > 1 else sys.stdin.read()
    if "Error:" not in text and "State 1:" not in text:
        print("# no counterexample trace found in input", file=sys.stderr)
        return 0
    states = parse_states(text)
    gherkin = to_gherkin(states)
    if gherkin is None:
        print("# trace parsed to zero states", file=sys.stderr)
        return 1
    sys.stdout.write(gherkin)
    return 0


def _selfcheck():
    """assert-based check: a 2-state trace yields Given/When/Then. Run: --selfcheck"""
    sample = """\
Error: Invariant Inv is violated.
State 1: <Initial predicate>
x = 0
y = TRUE
State 2: <Inc line 10, col 1 to line 10, col 8>
x = 1
y = TRUE
"""
    g = to_gherkin(parse_states(sample))
    assert "Given x = 0" in g, g
    assert "When Inc" in g, g
    assert "Then x becomes 1" in g, g
    assert "y becomes" not in g, "unchanged var must not appear in Then"
    # TLC 1.8 prints conjunct-form state vars (`/\ x = 1`); they must parse too.
    conj = parse_states("State 1: <Initial predicate>\n/\\ x = 0\nState 2: <Inc>\n/\\ x = 1\n")
    gc = to_gherkin(conj)
    assert "Given x = 0" in gc, gc
    assert "Then x becomes 1" in gc, gc
    print("selfcheck OK")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--selfcheck":
        _selfcheck()
    else:
        sys.exit(main())
