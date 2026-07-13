# loop-engineering 系の前提ツール

loopeng-* 各スキルが呼ぶ外部コマンドと駆動装置。未導入なら導入を促し、勝手に大規模インストールしない。

- `tlc` / `sany`: TLA+ のモデル検査器とパーサ。`apalache-mc`: 型チェック + 記号モデル検査(無限状態向け)。
  プラグインの flake が提供する(`./scripts/bootstrap.sh` 済みなら入っている)。
- `loop-outer` / `loop-middle` / `loop-inner`: `loopeng/Makefile.loopeng` 経由のループ駆動(fish 関数、または
  `make -f <このプラグインの loopeng ディレクトリ>/Makefile.loopeng loop-outer SPEC=<Name>` を直接叩いてもよい)。
  Makefile 本体・Python オラクル(`trace_to_gherkin.py`/`tla_mutate_oracle.py` 等)・テンプレートはこのプラグインの
  `loopeng/` 配下に同梱されている。fish 関数を使う場合は `LOOPENG_HOME` をこのプラグインの `loopeng/` へ向ける。
- 0 段ゲート(`hooks/loopeng-extract-gate.sh`)はこのプラグインの `hooks/hooks.json` で PreToolUse として配布される。
  プラグインを有効化していれば追加設定なしで効く。
- Gherkin ランナー(`cucumber-js` / `godog` 等)と要求トレーサビリティのツールは同梱しない。必要になったプロジェクトで個別に入れる。
  トレーサビリティ表を CI ゲート化するなら **OpenFastTrace**(被覆未達で非ゼロ終了)か **Doorstop**(`uv pip install doorstop`)。

`SPEC=<Name>` を通して呼ぶ。実行時の罠(TMPDIR/JDK 即死、TLC スクラッチ、トレース形式)は
loopeng-modelcheck スキルの [`references/troubleshooting.md`](../loopeng-modelcheck/references/troubleshooting.md)。
