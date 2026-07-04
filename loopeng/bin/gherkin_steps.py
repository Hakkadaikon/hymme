#!/usr/bin/env python3
"""pytest-bdd step definitions for the .feature files trace_to_gherkin.py emits.

The inner loop turns a TLC counterexample into Gherkin whose vocabulary is fixed
(see trace_to_gherkin.to_gherkin):

    Given <var> = <value>          # initial state, one per var
    And   <var> = <value>
    When  <action>                 # an action name
    Then  <var> becomes <value>    # vars that changed
    And   <var> becomes <value>
    Then  the state is unchanged   # no var changed

These steps parse that vocabulary into an expected state and diff it against the
real implementation. Everything implementation-specific lives behind one hook:

    Model.seed(var, value)               # apply one Given assignment
    Model.step(action) -> dict           # apply one action, return the new state

You write a Model for your system (C via subprocess, Rust via bindings, a pure
Python port, whatever) and register it through the `model` fixture in your own
conftest.py. The steps stay the same across every spec; wire them in with one
line of conftest:

    from gherkin_steps import register_steps, Model
    register_steps()                     # binds the 4 steps into this conftest

ponytail: values are compared as the strings TLC prints. A Model that returns
ints must stringify them (str(x)); we do not re-implement a TLA value parser.
Override Model.normalize if your representation differs from TLC's text form.

Run:  pytest --gherkin-terminal-reporter   (needs: pip install pytest-bdd)
"""
try:
    from pytest_bdd import given, when, then, parsers
except ModuleNotFoundError:  # let --selfcheck run without the test deps installed
    def _noop_deco(*_a, **_k):
        return lambda fn: fn

    given = when = then = _noop_deco

    class parsers:  # noqa: N801 -- mirrors pytest_bdd.parsers.parse signature
        @staticmethod
        def parse(s):
            return s


# --- the expected state the Gherkin describes, accumulated across steps -------

class Expected:
    """Mutable bag the Given/Then steps fill in; the When step drives the Model."""

    def __init__(self):
        self.vars = {}        # var -> expected value (TLC text form)


def register_steps():
    """Define the four steps in the *caller's* module namespace.

    pytest-bdd binds a step to the module where its decorator runs, so importing
    pre-decorated step functions from here would not register them. Call this at
    the top level of your conftest.py instead:

        from gherkin_steps import register_steps, Model
        register_steps()

    and supply `expected` + `model` fixtures (see Model's docstring)."""

    @given(parsers.parse("{var} = {value}"), stacklevel=2)
    def given_initial(expected, model, var, value):
        expected.vars[var] = value
        model.seed(var, value)

    @when(parsers.parse("{action}"), stacklevel=2)
    def when_action(expected, model, action):
        expected.last = model.normalize(model.step(action))

    @then(parsers.parse("{var} becomes {value}"), stacklevel=2)
    def then_becomes(expected, var, value):
        expected.vars[var] = value
        actual = expected.last.get(var)
        assert actual == value, f"{var}: expected {value!r}, model produced {actual!r}"

    @then("the state is unchanged", stacklevel=2)
    def then_unchanged(expected):
        for var, value in expected.vars.items():
            actual = expected.last.get(var)
            assert actual == value, (
                f"state was meant to be unchanged but {var} = {actual!r} "
                f"(expected {value!r})"
            )


# --- the hook you implement per project --------------------------------------

class Model:
    """Bridge from Gherkin actions to your real implementation.

    Subclass and override step(); seed() and normalize() have sane defaults.
    Register it as the `model` fixture in your conftest.py:

        @pytest.fixture
        def model():
            return MyModel()
    """

    def __init__(self):
        self.state = {}

    def seed(self, var, value):
        """Apply one Given assignment to the initial state. Override if your
        system can't be seeded var-by-var (e.g. needs a single constructor call)."""
        self.state[var] = value

    def step(self, action):
        """Apply one action, return the resulting state dict {var: value}.
        MUST be overridden -- this is the only truly project-specific part."""
        raise NotImplementedError(
            f"Model.step({action!r}): wire this to your implementation"
        )

    def normalize(self, state):
        """Coerce the implementation's state into the TLC text form the Gherkin
        uses (str values). Override if your encoding differs."""
        return {k: str(v) for k, v in state.items()}


def _selfcheck():
    """assert-based check: a fake Model replays the Counter counterexample and the
    Then-vs-Model diff holds. Drives the step bodies' logic without a pytest-bdd
    runtime (the decorators wrap the funcs, so we exercise the Model contract and
    the comparison the steps perform). Run: gherkin_steps.py --selfcheck"""

    class CounterModel(Model):
        def step(self, action):
            assert action == "Inc", action
            self.state["x"] = int(self.state["x"]) + 1
            return self.state

    m = CounterModel()
    m.seed("x", "0")                       # Given x = 0
    last = m.normalize(m.step("Inc"))      # When Inc
    assert last["x"] == "1", last          # Then x becomes 1  -> matches
    # an unchanged var must compare equal to its Given value
    m2 = Model.__new__(CounterModel)
    m2.state = {}
    m2.seed("y", "TRUE")
    assert m2.normalize({"y": "TRUE"})["y"] == "TRUE"
    print("selfcheck OK")


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "--selfcheck":
        _selfcheck()
    else:
        print(__doc__)
