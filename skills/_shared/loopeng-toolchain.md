# loop-engineering 系の前提ツール

loopeng-* 各スキルが呼ぶ外部コマンドと駆動装置。未導入なら導入を促し、勝手に大規模インストールしない。

- `tlc` / `sany`: TLA+ のモデル検査器とパーサ。`apalache-mc`: 型チェック + 記号モデル検査(無限状態向け)。
  プラグインの flake が提供する(`./scripts/bootstrap.sh` 済みなら入っている)。
- `loop-outer` / `loop-middle` / `loop-inner`: `loopeng/Makefile.loopeng` 経由のループ駆動(fish 関数、または
  `make -f <このプラグインの loopeng ディレクトリ>/Makefile.loopeng loop-outer SPEC=<Name>` を直接叩いてもよい)。
  Makefile 本体・Python オラクル(`trace_to_gherkin.py`/`tla_mutate_oracle.py` 等)・テンプレートはこのプラグインの
  `loopeng/` 配下に同梱されている。fish 関数を使う場合は `LOOPENG_HOME` をこのプラグインの `loopeng/` へ向ける。
- `loopeng/bin/` のスクリプト(`tla_mutate_oracle.py`、`trace_to_gherkin.py`、`feature_to_c.py`、`gherkin_steps.py`、`trace_check.py`、`smt_oracle.py`、`verifiability.py`、`tla_lint.sh`)は、flake の `skill-tools` を入れると同じ名前のコマンドとして PATH に入る。
  **検証対象のリポジトリに置くツールや文書からは、PATH のコマンドとして呼ぶ。** プラグインのキャッシュ(`~/.claude/plugins/cache/hymme/hymme/<版>/...`)の絶対パスを書かない。版が上がると切れ、ユーザー名もリポジトリに漏れる。
  リポジトリ側のツールが oracle を import して使うときは、`shutil.which("tla_mutate_oracle.py")` が返すパスを読み込む。別の版を使いたいときに備え、環境変数 `TLA_MUTATE_ORACLE`(スクリプトのパス)を先に見る形を勧める。この変数を読むのはリポジトリ側のツールで、hymme は読まない。
- 静的検査(`loopeng/bin/tla_lint.sh <spec.tla>`): SANY の構文・意味解析と、`@type:` 注釈がある spec の Apalache 型検査。SANY はエラーでも exit 0 を返すので出力で判定する。`loop-middle` / `loop-inner` は `lint` ターゲットで先に通し、`tlc` / `java ... tlc2.TLC` を直接叩く Bash は静的検査ゲート(`hooks/loopeng-lint-gate.sh`)が通らなければ止める。スクリプトの中から呼ぶ `tlc` は hook から見えないので、oracle は構文エラーの mutant を自前で invalid に分ける。
- `smt_oracle.py <model.py>`: SMT 経路の判定器(loopeng-smt)。Z3 の Python バインディングが要り、flake の `skill-tools` の python3 に同梱している。
- `trace_check.py [--all] <Spec.tla> <run.jsonl> [--cfg <cfg>] [--timeout SEC]`: 実ログと spec の突き合わせ(loopeng-tracecheck)。PATH の `tlc` を使う。
- `verifiability.py <台帳>`: 検証容易性の指標(verifiability)。lizard を `skill-tools` の python3 に同梱している。検証容易性ゲート(`hooks/verifiability-gate.sh`)が PATH から呼ぶので、無いと対象コードのある台帳の検証は止まる。
- 0 段ゲート(`hooks/loopeng-extract-gate.sh`)はこのプラグインの `hooks/hooks.json` で PreToolUse として配布される。
  プラグインを有効化していれば追加設定なしで効き、subagent(hymme:modeler)の Bash にも効く。台帳は cwd 相対の `tasks/loopeng/` を見るので、worktree 内で回すなら台帳もその worktree に置く。
- Gherkin ランナー(`cucumber-js` / `godog` 等)と要求トレーサビリティのツールは同梱しない。必要になったプロジェクトで個別に入れる。
  トレーサビリティ表を CI ゲート化するなら **OpenFastTrace**(被覆未達で非ゼロ終了)か **Doorstop**(`uv pip install doorstop`)。

`SPEC=<Name>` を通して呼ぶ。実行時の罠(TMPDIR/JDK 即死、TLC スクラッチ、トレース形式)は
loopeng-modelcheck スキルの [`references/troubleshooting.md`](../loopeng-modelcheck/references/troubleshooting.md)。
