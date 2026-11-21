# loop-engineering 系の前提ツール

loopeng-* 各スキルが呼ぶ外部コマンドと駆動装置。未導入なら導入を促し、勝手に大規模インストールしない。

- `tlc` / `sany`: TLA+ のモデル検査器とパーサ。`apalache-mc`: 型チェック + 記号モデル検査(無限状態向け)。
  プラグインの flake が提供する(`./scripts/bootstrap.sh` 済みなら入っている)。
- `loop-outer` / `loop-middle` / `loop-inner`: `loopeng/Makefile.loopeng` 経由のループ駆動。flake の `skill-tools` をインストールすると、
  同じ名前のコマンドとして PATH に入り、どのシェルからでも `loop-middle SPEC=<Name>` の形で呼べる。
  Makefile 本体・Python オラクル(`trace_to_gherkin.py`/`tla_mutate_oracle.py` 等)・テンプレートは同じ場所に入るので、
  `LOOPENG_HOME` を設定する必要は無い。
- `loopeng/bin/` のスクリプト(`tla_mutate_oracle.py`、`trace_to_gherkin.py`、`feature_to_c.py`、`gherkin_steps.py`、`trace_check.py`、`smt_oracle.py`、`verifiability.py`、`tla_lint.sh`)は、flake の `skill-tools` をインストールすると同じ名前のコマンドとして PATH に入る。
  **検証対象のリポジトリに置くツールや文書からは、PATH のコマンドとして呼ぶ。** プラグインのキャッシュ(`~/.claude/plugins/cache/hymme/hymme/<バージョン>/...`)の絶対パスを書かない。バージョンが上がると切れ、ユーザー名もリポジトリに漏れる。
  リポジトリ側のツールが oracle を import して使うときは、`shutil.which("tla_mutate_oracle.py")` が返すパスを読み込む。別のバージョンを使いたいときに備え、環境変数 `TLA_MUTATE_ORACLE`(スクリプトのパス)を先に見る形を勧める。この変数を読むのはリポジトリ側のツールで、hymme は読まない。
- 静的検査(`loopeng/bin/tla_lint.sh <spec.tla>`): SANY の構文・意味解析と、`@type:` 注釈がある spec の Apalache 型検査。SANY はエラーでも exit 0 を返すので出力で判定する。`loop-middle` / `loop-inner` は `lint` ターゲットで先に通し、`tlc` / `java ... tlc2.TLC` を直接叩く Bash は静的検査ゲート(`hooks/loopeng-lint-gate.sh`)が通らなければ止める。スクリプトの中から呼ぶ `tlc` は hook から見えないので、oracle は構文エラーの mutant を自前で invalid に分ける。
- `smt_oracle.py <model.py>`: SMT 経路の判定器(loopeng-smt)。Z3 の Python バインディングが要り、flake の `skill-tools` の python3 に同梱している。
- `trace_check.py [--all] <Spec.tla> <run.jsonl> [--cfg <cfg>] [--timeout SEC]`: 実ログと spec の突き合わせ(loopeng-tracecheck)。PATH の `tlc` を使う。
- `verifiability.py <台帳>`: 検証容易性の指標(verifiability)。lizard を `skill-tools` の python3 に同梱している。検証容易性ゲート(`hooks/verifiability-gate.sh`)が PATH から呼ぶので、無いと対象コードのある台帳の検証は止まる。
- `hymme <サブコマンド>`: ユーザーの承認の申請、状態遷移図、実ログの採取など、hook の記録に関わる操作をまとめたコマンド。`skill-tools` をインストールすると PATH に入る。このコマンド自身は記録に署名しない。機械で確かめられることを確かめて申請や結果を残し、コマンドを見ている hook が署名つきの記録を書く。コマンドの中で PATH を変えて実行すると、結果は記録されない。

  | コマンド | すること |
  | --- | --- |
  | `hymme claims check <名前>` | 確認の一覧の形を検査する |
  | `hymme claims request <名前>` | 一覧の承認を申請する |
  | `hymme chart draw <名前>` | TLC を回し、状態遷移図と規則ごとの結果を `<名前>.chart.md` に書く |
  | `hymme chart request <名前>` | 状態遷移図の承認を申請する |
  | `hymme capture <ログ> -- <コマンド>` | 実システムを動かしてログを採る |
  | `hymme specs` | この変更が触れている検証の対象の名前を出す |
  | `hymme exception request <検査> --until <日付> --reason <理由>` | 検査の例外を申請する(期限は最長90日)。`<検査>` に書けるのは `review` / `stages` / `surface` / `trace` / `stale` / `weaken` / `fix_without_escape` / `pr_body`。ユーザーの確認(確認の一覧、状態遷移図)と閉じていない欠陥の記録は例外で外せない |
  | `hymme escape open` / `verify` / `unreachable` / `list` / `stats` | 後段で見つかった欠陥の記録を扱う |

- 検証の入口を見る hook(`hooks/hymme_hook.py`)はこのプラグインの `hooks/hooks.json` で配布される。0 段の抽出台帳、確認の一覧の承認、reviewer の合格の記録、前提の記録を、検証の入口(`loop-*`、`smt_oracle.py`、`trace_check.py`、`tasks/fv/<Name>` での `lake build`、`tlc`・`apalache-mc` の直接の実行)の直前に検査する。
  プラグインを有効化していれば追加設定なしで効き、subagent(hymme:modeler)の Bash にも効く。検証の入口の検査は、コマンドを実行したディレクトリの `tasks/` を見る(実行した場所か引数のパスが `tasks/loopeng/`・`tasks/fv/` の中なら、その `tasks/` の手前)。`hymme` コマンドと統合の入口の検査はリポジトリ直下の `tasks/` を見る。両方が同じ台帳を指すように、台帳はリポジトリ直下の `tasks/` に置き、入口はリポジトリ直下から実行する。worktree 内で回すなら台帳もその worktree に置く。hook が書く記録は git の共通ディレクトリにあり、worktree をまたいで共有される([`stealth-artifacts.md`](stealth-artifacts.md) の「hook の記録」)。
  スクリプトや Makefile の中から呼んだ検証の入口は hook から見えず、記録が残らない。記録が要る実行(実ログの突き合わせ、突き合わせのコマンドなど)は Bash から直接実行する。
- Gherkin ランナー(`cucumber-js` / `godog` 等)と要求トレーサビリティのツールは同梱しない。必要になったプロジェクトで個別にインストールする。
  トレーサビリティ表を CI ゲート化するなら **OpenFastTrace**(被覆未達で非ゼロ終了)か **Doorstop**(`uv pip install doorstop`)。

`SPEC=<Name>` を通して呼ぶ。実行時の罠(TMPDIR/JDK 即死、TLC スクラッチ、トレース形式)は
loopeng-modelcheck スキルの [`references/troubleshooting.md`](../loopeng-modelcheck/references/troubleshooting.md)。
