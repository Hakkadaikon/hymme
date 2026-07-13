# hymme

設計検証・テスト設計・形式検証のスキル群と開発ワークフロースキル、それらが必要とする Nix ツールチェインをまとめた Claude Code プラグインマーケットプレイス。

## 収録スキル

検証系は「入口ルーター + 工程スキル」の構成をとる。ルーターが局面を判定し、対応する工程スキルへ振り分ける。

- **loop-engineering**：自然言語の要求を TLA+ で検査可能な設計へ厳密化する 3 重ループの入口ルーター。
  - **loopeng-extract**(0 段)：仕様・要求から要件を網羅抽出する。
  - **loopeng-formalize**(外)：EARS 記法と状態/ドメインモデルへ構造化し、TLA+ spec に落とす。
  - **loopeng-modelcheck**(中)：TLC でモデル検査し、spec 自体を mutation oracle で点検する。
  - **loopeng-gherkin**(内)：反例トレースを Gherkin の受け入れ仕様に落とす。
- **test-design**：テスト設計・既存テストレビューの入口ルーター。
  - **test-extract**(0 段)：テストすべき振る舞いを網羅抽出し、台帳にする。
  - **test-catalog**：手法カタログ(索引専用)。各振る舞いへ、同値分割・状態遷移・mutation testing・TDDサイクルなど個別スキル化された40のテスト技法から手法を割り当てる。
  - **test-verify**：実装への橋渡し・実行ゲート・回帰固定を行う。
- **formal-verification**：雑な仕様を Lean 4 の形式仕様へ落とし込み、証明で検証し(proof-repair ループ)、証明済みの性質を test-first 実装へ橋渡しする。

開発ワークフロースキル。

- **diff-review**：差分を多観点で並列レビューする(diff-reviewer agent が担当)。過剰設計だけを見る場合は code-reviewer agent を使う。
- **commit-flow**：コミットの粒度判断と計画。実務の分割・実行は micro-commit スキルが担う。
- **micro-commit**：変更を~30-50行の論理単位に分割し conventional commit で連続コミットする実務手順。
- **test-targeted**：変更に関係するテストだけを絞り込んで実行する。
- **gh-ci-investigate**：GitHub CI の失敗を調査する。
- **rebase-flow** / **reset-flow**：履歴破壊操作の安全運用(同梱の git-guard hook が arm なしの実行を機械的にブロックする)。
- **pr-create**：PR を作成する。

agents として次を同梱する。

- **diff-reviewer**：diff-review のワーカー(多観点レビュー)。
- **code-reviewer**：ponytail-review 観点(過剰設計)だけを見るレビュー担当。
- **coder**：ponytail(最小・YAGNI)と TDD で実装・修正・リファクタを行う担当。formal-verification / loop-engineering / test-design が必要な局面ではそれぞれ prover / modeler / test-design へ委譲する。
- **modeler**：loop-engineering(TLA+)でモデル検査を行う担当。1 spec に集中し、完了前に loop-engineering-reviewer で外部検査する。
- **prover**：formal-verification(Lean 4)で証明を行う担当。1 性質に集中し、完了前に formal-verification-reviewer で外部検査する。
- **loop-engineering-reviewer** / **test-design-reviewer** / **formal-verification-reviewer**：各スキル群の完了前ゲートを担う外部コンプライアンスレビュアー。

## インストール(Claude Code)

```
/plugin marketplace add Hakkadaikon/hymme
/plugin install hymme@hymme
```

## ツールチェイン(Nix)

スキルは TLA+(TLC/SANY)、Apalache、make、python3、Lean(elan 経由)を外部コマンドとして呼ぶ。
flake がこれらをまとめて提供する。

一括セットアップ。
`nix` が無ければ先に Determinate Nix を入れる。
システム全体への変更なので実行前に確認を求める(非対話で進めるなら `HYMME_ASSUME_YES=1`)。

```sh
./scripts/bootstrap.sh          # nix develop — ツールチェインを PATH に載せた dev シェル
./scripts/bootstrap.sh install  # nix profile install .#skill-tools — profile に永続化
```

すでに Nix があるなら直接実行してもよい。

```sh
nix develop                       # ツールチェインを PATH に載せた dev シェル
nix profile install .#skill-tools # または profile にインストール
```

これで `tlc` / `sany` / `apalache-mc` / `lake` / `lean` が使えるようになる。
nixpkgs には TLA+ と Apalache の公式パッケージが無いため、flake は固定したリリース成果物を取得して JRE でラップする。
バージョンを上げるときは `flake.nix` の URL とハッシュを揃えて更新する。

次のものは含めていない(必要になったプロジェクトで個別に入れる)。

- Gherkin ランナー：`cucumber-js`(npm)や `godog`(`go install`)。nixpkgs に無い。
- 要求のトレーサビリティ用の `doorstop`：`uv pip install doorstop`。
