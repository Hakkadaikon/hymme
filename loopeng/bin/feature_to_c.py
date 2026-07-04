#!/usr/bin/env python3
"""Inner-loop glue (other half of trace_to_gherkin.py): turn a machine-generated
Gherkin feature into a C test that drives the implementation through the same
state-machine actions and CHECKs the post-state. For freestanding / no-libc
targets where no Cucumber runner exists. LAST RESORT: any hosted language has a
native Cucumber (pytest-bdd, godog, cucumber-js/-jvm/-rs, ...) -- use that and
write glue, don't reach for a per-language generator. This exists only because
freestanding C has no runner (cucumber-cpp needs C++/libc + a Ruby wire peer).

It consumes the *regular* form trace_to_gherkin.py emits:

    Given <var> = <value>            # initial state (ignored: we build fresh and
    When  <ActionName>               #   replay the actions)
    Then  <var> becomes <value>      # post-action assertions -> CHECK(...)
    And   <var> becomes <value>

Everything implementation-specific lives in a JSON mapping file you keep in your
project (the C names, enum literals, helper calls are all yours), exactly like
gherkin_steps.py keeps it behind Model.step. This tool itself knows no domain.

Mapping JSON (see --example for a full one):
    {
      "header": "<C preamble: includes, the fresh() helper, run_bdd() opener>",
      "footer": "}\\n",                     # closes run_bdd(); default "}\\n"
      "fresh":  "    bdd_fresh(&c);",        # per-scenario setup line(s)
      "decl":   "    ws_conn c;",            # per-scenario declaration line(s)
      "actions": { "Handshake": "ws_lc_handshake(&c);", ... },
      "vars": {                              # TLA var -> C field + value literals
        "state": {"field": "c.state", "values": {"OPEN": "WS_OPEN", ...}}
      },
      "param_actions": {                     # actions whose arg comes from the
        "StartFrag": {"var": "frag", "call": "ws_lc_start_frag(&c, {value});"}
      }                                      #   following Then's mapped value
    }

Usage:
    feature_to_c.py --map ws.json Spec.feature > generated_bdd.c
    feature_to_c.py --map ws.json < Spec.feature
    feature_to_c.py --example > ws.json        # print a sample mapping
    feature_to_c.py --selfcheck

ponytail: only the machine form (When <Action> / Then <var> becomes <value>)
from trace_to_gherkin.py is parsed. Hand-written prose Then lines are skipped --
keep those in your own test source.
"""
import json
import re
import sys

STATE_RE = re.compile(r"^\s*(Given|When|Then|And|But|Scenario|Feature|Background)\b(.*)$")
ASSIGN_RE = re.compile(r"^([A-Za-z_]\w*)\s+becomes\s+(\S+)$")  # "frag becomes TEXT"


def cval(mapping, var, val):
    spec = mapping["vars"][var]
    values = spec["values"]
    if val not in values:
        raise SystemExit(f"unknown value {val!r} for var {var!r} (add it to vars.{var}.values)")
    return spec["field"], values[val]


def emit_scenario(mapping, name, steps):
    """steps: list of (kind, text). Returns C lines for one scenario block."""
    out = [f"    // Scenario: {name}"]
    out += mapping.get("decl", "").splitlines()
    out += mapping.get("fresh", "").splitlines()
    actions = mapping["actions"]
    param_actions = mapping.get("param_actions", {})
    vars_ = mapping["vars"]
    pending = None  # a param_action waiting for its Then to supply the argument
    for kind, text in steps:
        if kind == "When":
            act = text.strip()
            if act in param_actions:
                pending = act           # need the next Then to know the value
            elif act in actions:
                out.append(f"    {actions[act]}")
            else:
                raise SystemExit(f"unknown action {act!r} in scenario {name!r} "
                                 f"(add it to actions or param_actions)")
        elif kind in ("Then", "And", "But"):
            m = ASSIGN_RE.match(text.strip())
            if not m:
                continue                # narrative/prose Then: skip
            var, val = m.group(1), m.group(2)
            if var not in vars_:
                continue                # var out of this mapping's scope: skip
            if pending and param_actions[pending]["var"] == var:
                _, cv = cval(mapping, var, val)
                out.append("    " + param_actions[pending]["call"].format(value=cv))
                pending = None
            field, cv = cval(mapping, var, val)
            out.append(f'    CHECK({field} == {cv}, "{name}: {var}={val}");')
    return out


def parse(text):
    scenarios, name, steps = [], None, []
    for line in text.splitlines():
        m = STATE_RE.match(line)
        if not m:
            continue
        kw, rest = m.group(1), m.group(2).strip().lstrip(":").strip()
        if kw == "Scenario":
            if name is not None:
                scenarios.append((name, steps))
            name, steps = rest, []
        elif kw in ("When", "Then", "And", "But", "Given") and name is not None:
            steps.append((kw, rest))
    if name is not None:
        scenarios.append((name, steps))
    return scenarios


def render(mapping, scenarios):
    body = [mapping["header"]]
    for name, steps in scenarios:
        body.append("    {")
        body.extend(emit_scenario(mapping, name, steps))
        body.append("    }")
    body.append(mapping.get("footer", "}\n"))
    return "\n".join(body)


EXAMPLE = {
    "header": (
        "// GENERATED by feature_to_c.py from a TLA+-derived .feature. Do not hand-edit:\n"
        "// change the model -> re-derive the feature -> regenerate this file.\n"
        "static uint8_t bdd_buf[64];\n"
        "static void bdd_fresh(ws_conn *c) {\n"
        "    ws_conn_init(c, WS_ROLE_SERVER, bdd_buf, sizeof bdd_buf);\n"
        "}\n"
        "void run_bdd(void);\n"
        "void run_bdd(void) {"
    ),
    "footer": "}\n",
    "decl": "    ws_conn c;",
    "fresh": "    bdd_fresh(&c);",
    "actions": {
        "Handshake": "ws_lc_handshake(&c);",
        "SendClose": "ws_lc_send_close(&c);",
        "RecvClose": "ws_lc_recv_close(&c);",
        "FinishFrag": "ws_lc_finish_frag(&c);",
        "Terminated": "/* terminal self-loop: no-op */",
    },
    "param_actions": {
        "StartFrag": {"var": "frag", "call": "ws_lc_start_frag(&c, {value});"},
    },
    "vars": {
        "state": {"field": "c.state", "values": {
            "CONNECTING": "WS_CONNECTING", "OPEN": "WS_OPEN",
            "CLOSING": "WS_CLOSING", "CLOSED": "WS_CLOSED"}},
        "frag": {"field": "c.frag", "values": {
            "NONE": "WS_FRAG_NONE", "TEXT": "WS_FRAG_TEXT", "BIN": "WS_FRAG_BIN"}},
        "sentClose": {"field": "c.sent_close", "values": {"TRUE": "1", "FALSE": "0"}},
        "rcvdClose": {"field": "c.rcvd_close", "values": {"TRUE": "1", "FALSE": "0"}},
    },
}


def main():
    args = sys.argv[1:]
    if "--example" in args:
        json.dump(EXAMPLE, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0
    mapping = None
    if "--map" in args:
        i = args.index("--map")
        mapping = json.load(open(args[i + 1]))
        del args[i:i + 2]
    if mapping is None:
        raise SystemExit("need --map <mapping.json> (or --example to print one)")
    src = open(args[0]).read() if args else sys.stdin.read()
    scenarios = parse(src)
    if not scenarios:
        print("// no scenarios parsed", file=sys.stderr)
        return 1
    sys.stdout.write(render(mapping, scenarios))
    return 0


def _selfcheck():
    """assert-based check: a tiny domain-neutral mapping drives the generator.
    No WebSocket names here -- the tool must be project-agnostic. Run: --selfcheck"""
    mapping = {
        "header": "void run_bdd(void) {",
        "decl": "    counter c;",
        "fresh": "    c_init(&c);",
        "actions": {"Inc": "c_inc(&c);"},
        "param_actions": {"SetMode": {"var": "mode", "call": "c_set_mode(&c, {value});"}},
        "vars": {
            "x": {"field": "c.x", "values": {"0": "0", "1": "1"}},
            "mode": {"field": "c.mode", "values": {"FAST": "MODE_FAST"}},
        },
    }
    feat = """\
Feature: x
  Scenario: inc then set
    Given x = 0
    When Inc
    Then x becomes 1
    When SetMode
    Then mode becomes FAST
"""
    txt = render(mapping, parse(feat))
    assert "void run_bdd(void) {" in txt, txt
    assert "    counter c;" in txt, txt
    assert "c_inc(&c);" in txt, txt
    assert 'CHECK(c.x == 1, "inc then set: x=1");' in txt, txt
    assert "c_set_mode(&c, MODE_FAST);" in txt, txt          # param_action resolved
    assert 'CHECK(c.mode == MODE_FAST' in txt, txt
    # an unmapped var must be skipped, not crash
    txt2 = render(mapping, parse("Feature: y\n  Scenario: s\n    When Inc\n    Then ghost becomes 9\n"))
    assert "ghost" not in txt2, txt2
    print("selfcheck OK")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--selfcheck":
        _selfcheck()
    else:
        sys.exit(main())
