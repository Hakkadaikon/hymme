# hymme

[superpowers](https://github.com/obra/superpowers) を前提に、設計検証(TLA+)・テスト設計・形式検証(Lean 4)の 3 系統と git/レビュー運用のスキル、専用 agents を足す Claude Code プラグイン。superpowers 本体もこの marketplace から入れられる(動作確認版 6.3.0)。工程を決めるのは superpowers、hymme はその各工程に検証と運用を差し込む。差し込み位置の地図は `using-hymme` スキルで、セッション開始時に自動注入される。

必要な Nix ツールチェイン(TLA+/Apalache/Lean)も flake で配る。

## superpowers との役割分担

| 局面 | superpowers が担う | hymme が足す |
| --- | --- | --- |
| 設計 | brainstorming(spec 化、Architectural 経路) | 設計後・spec 前に loop-engineering の 2 問ゲート / formal-verification の性質カタログ |
| 計画 | writing-plans(Task / Step) | spec 承認後に test-design で T-ID 台帳 → Task に落とす |
| 実装 | subagent-driven-development / executing-plans、test-driven-development | implementer は coder agent(ponytail + TDD 契約)。prover / modeler は controller が別 dispatch、完了ゲートで各 reviewer |
| コミット | (規約なし) | commit-flow(粒度)+ micro-commit(実務) |
| レビュー | task review(SDD の task-reviewer-prompt.md)/ final review(requesting-code-review) | 多観点 diff-review。PR 前は hook で diff-review 証跡を必須化 |
| PR | finishing-a-development-branch | pr-create |
| バグ | systematic-debugging | gh-ci-investigate(Phase 1 の証拠収集) |
| 訂正 | receiving-code-review | review-feedback(水平展開・lessons) |
| 台帳 | SDD の ledger 形式 | ledger-flow(それ以外の進捗・引き継ぎ文書) |
| 履歴 | using-git-worktrees | rebase-flow / reset-flow + git-guard hook |

superpowers の `using-superpowers` と hymme の `using-hymme` はどちらもセッション開始時に注入される。前者が「スキルを使え」、後者が「どこで hymme を使うか」を決める。

## 収録スキル

検証系は「入口ルーター + 工程スキル」の構成をとる。ルーターが局面を判定し、対応する工程スキルへ振り分ける。

- **loop-engineering**：自然言語の要求を TLA+ で検査可能な設計へ厳密化する 3 重ループの入口ルーター。
  - **loopeng-extract**(0 段)：仕様・要求から要件を網羅抽出する。信頼境界ごとに STRIDE の6観点(入力のパースや長さ・オフセットの算術があれば CWE Top 25 も)で異常系の要件を突き合わせる。
  - **loopeng-formalize**(外)：EARS 記法と状態/ドメインモデルへ構造化し、TLA+ spec に落とす。
  - **loopeng-modelcheck**(中)：TLC でモデル検査し、spec 自体を mutation oracle で点検する。最後に、初期状態・不変条件・遷移の文面を独立した読み手に平文へ戻させ、要件と一致するか(向きの取り違え・空成立が無いか)を確かめる。
  - **loopeng-gherkin**(内)：反例トレースを Gherkin の受け入れ仕様に落とす。
- **test-design**：テスト設計・既存テストレビューの入口ルーター。
  - **test-extract**(0 段)：テストすべき振る舞いを網羅抽出し、台帳にする。
  - **test-catalog**：手法カタログ(索引専用)。各振る舞いへ、同値分割・状態遷移・mutation testing・TDDサイクルなど個別スキル化された40のテスト技法から手法を割り当てる。
  - **test-verify**：実装への橋渡し・実行ゲート・回帰固定を行う。
- **formal-verification**：雑な仕様を Lean 4 の形式仕様へ落とし込み、証明で検証し(proof-repair ループ)、証明済みの性質を test-first 実装へ橋渡しする。証明が通った後、定理の文面を独立した読み手に平文へ戻させて性質カタログと突き合わせ、通っても要件と違うことを言う定理を見つけて直す。

開発ワークフロースキル。

- **diff-review**：差分を多観点で並列レビューする(diff-reviewer agent が担当)。`conformance` レンズは、不変条件・性質を実装が全経路で守るかを性質ごとに論証させ、論証が切れた経路だけを指摘する。過剰設計だけを見る場合は code-reviewer agent を使う。
- **commit-flow**：コミットの粒度判断と計画。実務の分割・実行は micro-commit スキルが担う。
- **micro-commit**：変更を~30-50行の論理単位に分割し conventional commit で連続コミットする実務手順。
- **test-targeted**：変更に関係するテストだけを絞り込んで実行する。
- **gh-ci-investigate**：GitHub CI の失敗を調査する。
- **review-feedback**：レビュー指摘や自力検知した失敗に対応し、原因分析・水平展開・観点の埋め込みまで行う。
- **ledger-flow**：進捗台帳・計画/引き継ぎ文書の運用(記法の一本化・証跡ポインタ・closed 化)。
- **rebase-flow** / **reset-flow**：履歴破壊操作の安全運用(同梱の git-guard hook が arm なしの実行を機械的にブロックする)。
- **pr-create**：PR を作成する。

agents として次を同梱する。呼び出しは subagent_type `hymme:<name>`。

- **coder**:SDD の implementer 契約(spec → 実装 → 自己検証 → 報告)を、ponytail(最小・YAGNI)と TDD で遂行する。prover / modeler への委譲はしない。形式検証・モデル検査が必要なら「必要」と報告して controller に返す。
- **modeler**:loop-engineering(TLA+)でモデル検査を行う担当。1 spec に集中して結果を返す。loop-engineering-reviewer への hand-off は controller が行う。
- **prover**:formal-verification(Lean 4)で証明を行う担当。1 性質に集中して結果を返す。formal-verification-reviewer への hand-off は controller が行う。
- **diff-reviewer**:diff-review のワーカー(多観点レビュー)。
- **code-reviewer**:ponytail-review 観点(過剰設計)だけを見るレビュー担当。
- **loop-engineering-reviewer** / **test-design-reviewer** / **formal-verification-reviewer**:各系統の完了ゲート。controller が modeler / prover / test-design の成果を渡して外部検査させる。

coder と code-reviewer は [ponytail](https://github.com/DietrichGebert/ponytail) プラグインを Skill ツールで呼ぶ(soft dependency、未導入なら該当手順をスキップ)。ponytail は自身の marketplace から入れる:`/plugin marketplace add DietrichGebert/ponytail` → `/plugin install ponytail@ponytail`。

## インストール(Claude Code)

superpowers が前提。hymme の marketplace から両方入れる。

```
/plugin marketplace add Hakkadaikon/hymme
/plugin install superpowers@hymme
/plugin install hymme@hymme
```

superpowers は `/plugin install superpowers@claude-plugins-official` で入れても同じ(同一プラグイン)。**どちらか一方だけ**入れる。両方入れるとスキルと SessionStart hook が二重になる。すでに official 版が入っているなら `superpowers@hymme` は入れない。

動作確認版は superpowers 6.3.0。marketplace の entry は sha を固定しない(`/plugin update superpowers@hymme` で上流に追従する)。

更新は `/plugin marketplace update hymme` → `/plugin update hymme@hymme`(hymme marketplace は autoUpdate 無効)。反映には再起動が要る。

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
