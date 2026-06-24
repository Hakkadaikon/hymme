# hymme

A Claude Code plugin marketplace bundling two skills with the Nix toolchain they need.

## Skills

- **loop-engineering** — NL → EARS → TLA+ → Gherkin. Structures natural-language
  requirements, model-checks the design with TLC/Apalache, and turns counterexamples
  into Gherkin acceptance specs.
- **test-design** — a catalog and selection workflow for designing tests (and
  reviewing existing ones): exhaustively extract behaviors-under-test and assign a
  fitting technique to each.
- **formal-verification** — autoformalize a rough spec into a Lean 4 spec, verify it
  by proof (proof-repair loop), then bridge the proven properties into a test-first
  implementation.

## Install (Claude Code)

```
/plugin marketplace add Hakkadaikon/hymme
/plugin install hymme@hymme
```

## Toolchain (Nix)

The skills shell out to TLA+ (TLC/SANY), Apalache, make, python3, and Lean (via elan).
The flake provides them all.

One-shot bootstrap (installs Determinate Nix first if `nix` is missing — prompts
before the system-level install; set `HYMME_ASSUME_YES=1` for non-interactive):

```sh
./scripts/bootstrap.sh          # nix develop — dev shell with the toolchain on PATH
./scripts/bootstrap.sh install  # nix profile install .#skill-tools — persist into profile
```

Or directly, if you already have Nix:

```sh
nix develop                 # dev shell with the toolchain on PATH
nix profile install .#skill-tools # or install into your profile
```

`tlc` / `sany` / `apalache-mc` / `lake` / `lean` become available. nixpkgs has no
official TLA+/Apalache package, so the flake fetches pinned release artifacts and
wraps them with a JRE; bump the URLs and hashes in `flake.nix` together.

Not provisioned (install per-project only when actually needed):

- Gherkin runners — `cucumber-js` (npm) / `godog` (`go install`); not in nixpkgs.
- `doorstop` for requirement traceability — `uv pip install doorstop`.
