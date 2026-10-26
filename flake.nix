{
  description = "hymme: toolchain for the loop-engineering and test-design skills";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-26.05-darwin";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:

  flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };

      # Loop engineering: TLA+ (TLC/SANY) and Apalache. nixpkgs has no official
      # package, so we fetch the release artifacts and wrap them with a JRE.
      # Versions/hashes pinned via nix-prefetch-url; bump both together.
      tla2tools = pkgs.fetchurl {
        url = "https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar";
        hash = "sha256-0VZV7q/0s/ez1lxGuDi8DzXRMbLvSx5HNom2LJjUcm8=";
      };
      tlaplus = pkgs.runCommand "tlaplus-1.8.0" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
        mkdir -p $out/share/tlaplus $out/bin
        cp ${tla2tools} $out/share/tlaplus/tla2tools.jar
        makeWrapper ${pkgs.jdk}/bin/java $out/bin/tlc \
          --add-flags "-cp $out/share/tlaplus/tla2tools.jar tlc2.TLC"
        makeWrapper ${pkgs.jdk}/bin/java $out/bin/sany \
          --add-flags "-cp $out/share/tlaplus/tla2tools.jar tla2sany.SANY"
      '';

      apalacheSrc = pkgs.fetchurl {
        url = "https://github.com/apalache-mc/apalache/releases/download/v0.62.4/apalache-0.62.4.tgz";
        hash = "sha256-t4G1O7oy+sFKwuArAzLh3C7cZMt7hQwGCNgULMeqLvQ=";
      };
      apalache = pkgs.runCommand "apalache-0.62.4" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
        mkdir -p $out
        tar xzf ${apalacheSrc} -C $out --strip-components=1
        # The launcher's `#!/usr/bin/env bash` doesn't resolve in the nix sandbox.
        patchShebangs $out/bin
        # The shipped bin/apalache-mc launcher needs a JRE on PATH and JAVA_HOME.
        wrapProgram $out/bin/apalache-mc \
          --prefix PATH : ${pkgs.jdk}/bin \
          --set JAVA_HOME ${pkgs.jdk}
      '';

      # python3 with what the oracles import: Z3 (smt_oracle.py), lizard (verifiability.py).
      python = pkgs.python3.withPackages (ps: [ ps.z3-solver ps.lizard ]);

      # The loop oracles and lint (loopeng/bin) as commands on PATH, so a
      # repository can call them without pointing at a versioned plugin cache.
      loopengTools = pkgs.runCommand "hymme-loopeng-tools" { buildInputs = [ python pkgs.bashNonInteractive ]; } ''
        mkdir -p $out/bin
        install -m 755 ${./loopeng/bin}/{tla_mutate_oracle,trace_to_gherkin,feature_to_c,gherkin_steps,trace_check,smt_oracle,verifiability}.py ${./loopeng/bin}/tla_lint.sh $out/bin/
        patchShebangs $out/bin
      '';

      tools = [
        loopengTools
        tlaplus
        apalache
        pkgs.gnumake
        python       # runs the loop oracles (mutate / trace->gherkin / trace check / smt)
        pkgs.elan    # formal verification: Lean 4 toolchain manager (lake + lean)
        # ponytail: doorstop isn't in nixpkgs; `uv pip install doorstop` only when
        # requirement traceability is actually needed. python3 alone runs the loop.
        # Gherkin runners (cucumber-js / godog) aren't in nixpkgs; install per-project
        # via npm / go install when a runnable .feature is actually needed.
      ];

      # hymme 自身のスクリプトの品質ゲート(scripts/lint.sh)。skill-tools には入れない(開発用)
      lintTools = [ pkgs.ruff pkgs.shellcheck pkgs.shfmt ];
    in
    {
      packages = {
        inherit tlaplus apalache loopengTools;
        # Named `skill-tools` (not `tools`) so it shows a distinct profile entry
        # from dotfiles' own `tools`, which lets `nix profile upgrade skill-tools`
        # target it by name.
        skill-tools = pkgs.buildEnv {
          name = "hymme-skill-tools";
          paths = tools;
        };
        default = self.packages.${system}.skill-tools;
      };

      checks.reviewer-checklist = pkgs.runCommand "reviewer-checklist" { } ''
        bash ${self}/scripts/check-reviewer-checklist.test.sh
        touch $out
      '';

      checks.collect-diff = pkgs.runCommand "collect-diff" { nativeBuildInputs = [ pkgs.git ]; } ''
        export HOME=$TMPDIR
        bash ${self}/scripts/collect-diff.test.sh
        touch $out
      '';

      checks.session-start = pkgs.runCommand "session-start" { nativeBuildInputs = [ pkgs.python3 pkgs.gawk ]; } ''
        bash ${self}/scripts/session-start.test.sh
        touch $out
      '';

      checks.doc-refs = pkgs.runCommand "doc-refs" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        cd ${self}
        bash scripts/check-doc-refs.test.sh
        touch $out
      '';

      checks.test-design-extract-gate = pkgs.runCommand "test-design-extract-gate" { nativeBuildInputs = [ pkgs.python3 pkgs.git ]; } ''
        cp -r ${self} src && chmod -R u+w src
        HOME=$TMPDIR bash src/scripts/test-design-extract-gate.test.sh
        touch $out
      '';

      # Runs against the whole skill-tools env on purpose: the tools must be on
      # the PATH a user gets, next to the sany they call.
      checks.loopeng-tools = pkgs.runCommand "loopeng-tools" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        bash ${self}/scripts/loopeng-tools.test.sh ${self.packages.${system}.skill-tools}/bin
        touch $out
      '';

      checks.loopeng-lint = pkgs.runCommand "loopeng-lint" { nativeBuildInputs = [ tlaplus apalache pkgs.python3 pkgs.git ]; } ''
        cp -r ${self} src && chmod -R u+w src
        bash src/scripts/loopeng-lint.test.sh
        touch $out
      '';

      checks.loopeng-trace-check = pkgs.runCommand "loopeng-trace-check" { nativeBuildInputs = [ tlaplus python ]; } ''
        cp -r ${self} src && chmod -R u+w src
        bash src/scripts/loopeng-trace-check.test.sh
        touch $out
      '';

      checks.loopeng-smt-oracle = pkgs.runCommand "loopeng-smt-oracle" { nativeBuildInputs = [ python ]; } ''
        bash ${self}/scripts/loopeng-smt-oracle.test.sh
        touch $out
      '';

      checks.verifiability = pkgs.runCommand "verifiability" { nativeBuildInputs = [ python ]; } ''
        cp -r ${self} src && chmod -R u+w src
        bash src/scripts/verifiability.test.sh
        touch $out
      '';

      checks.lint = pkgs.runCommand "lint" { nativeBuildInputs = lintTools ++ [ pkgs.bashNonInteractive pkgs.findutils pkgs.python3 ]; } ''
        cp -r ${self} src && chmod -R u+w src
        bash src/scripts/lint.sh
        touch $out
      '';

      devShells.default = pkgs.mkShell {
        buildInputs = tools ++ lintTools;
      };
    }
  );
}
