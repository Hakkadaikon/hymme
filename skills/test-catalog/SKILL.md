---
name: test-catalog
description: >
  test-design の手法選定工程。テスト手法カタログ(references 30 本超)への索引と、
  T-ID 台帳の各振る舞いに手法を割り当てるワークフロー。
  「どのテスト手法を使うべきか」、または手法名(同値分割、境界値、ドメイン分析、デシジョンテーブル、
  状態遷移、ペアワイズ、直交表、T-way、判定/条件網羅、MC/DC、基底パス、構文テスト、contract/Pact、
  property based、mutation、メタモルフィック、ゴールデン、承認、仕様化テスト、チェックリストベース、
  テストダブル、LLM・非決定的出力のテスト、EARS)を挙げられたとき、
  「テストが flaky」「期待値が用意しにくい」「テストが脆い」の困りごとから手法を探すとき、
  または test-design ルーターから手法選定として委譲されたときに使用する。
  前提: test-extract の T-ID 台帳(tasks/test-design/<対象名>.md)が完成していること。
  無ければ先に test-extract へ戻る(単発の手法質問なら台帳なしで索引だけ引いてよい)。
---

# test-catalog (手法カタログと割り当て)

抽出した各 `T-ID` に、どのテスト手法で検証するかを割り当てる。
**このファイルは索引**。全手法の定義、目的、TypeScript example は `references/` に厳密に置き、
**割り当てた手法が載っている reference だけを読む**(全部は読まない)。
迷ったら、まず種別(正常系、境界、異常系、非機能)から下表で当たりをつける。

**前提**: T-ID 台帳があること。無ければ **test-extract** へ戻る(手法の単発質問は索引だけで可)。

## 索引

| 何を検証したいか | 読む reference |
| --- | --- |
| なぜその技法が要るか迷ったとき(テストの7原則) | [`references/testing-principles.md`](references/testing-principles.md) |
| 粒度の選択(サービス内部: unit/integration) | [`references/levels.md`](references/levels.md) |
| 粒度の選択(サービス間: component/contract/スキーマ検証) | [`references/levels-service.md`](references/levels-service.md) |
| 粒度の選択(システム全体・広域: system/E2E/UAT) | [`references/levels-system.md`](references/levels-system.md) |
| 粒度の選択(システム全体・運用: smoke/sanity/regression) | [`references/levels-operational.md`](references/levels-operational.md) |
| テスト戦略・配分(ピラミッド/トロフィー、関心事の階層化、リスクベース) | [`references/strategy-allocation.md`](references/strategy-allocation.md) |
| テスト戦略・運用(シフトレフト/ライト、環境・データ戦略、フレーキー方針、CI ゲーティング) | [`references/strategy-operations.md`](references/strategy-operations.md) |
| 仕様から導く・入力空間の分割(同値分割、境界値、ドメイン分析、デシジョンテーブル) | [`references/blackbox-partition.md`](references/blackbox-partition.md) |
| 仕様から導く・履歴と状態(状態遷移、CRUD/ライフサイクル、禁止仕様からの導出) | [`references/blackbox-state.md`](references/blackbox-state.md) |
| 条件の論理関係から組合せを縮約(原因結果グラフ、クラシフィケーションツリー) | [`references/blackbox-cause-effect.md`](references/blackbox-cause-effect.md) |
| 因子の被覆で組合せを縮約(ペアワイズ、直交表、T-way) | [`references/blackbox-covering.md`](references/blackbox-covering.md) |
| 経験・業務フローから導く(ユースケース、シナリオ、構文テスト) | [`references/experience-scenario.md`](references/experience-scenario.md) |
| 経験・過去バグをチェックリスト化して消し込む、壊れそうな入力を狙い撃つ(チェックリストベース、エラー推測) | [`references/experience-checklist.md`](references/experience-checklist.md) |
| 乱数や即興で揺さぶる、仕様が固まる前に触って調べる(ランダム/アドホックファジング、探索的、アドホック) | [`references/experience-exploratory.md`](references/experience-exploratory.md) |
| 構造網羅・制御フロー基本(C0/C1、条件、判定/条件) | [`references/whitebox-controlflow-basic.md`](references/whitebox-controlflow-basic.md) |
| 構造網羅・経路と独立影響(MC/DC、多重条件、パス、基底パス) | [`references/whitebox-controlflow-path.md`](references/whitebox-controlflow-path.md) |
| 構造網羅・ループとデータフロー(ループテスト、def-use) | [`references/whitebox-dataflow-loop.md`](references/whitebox-dataflow-loop.md) |
| テストの強さを測る(mutation、テストの欠陥検出力) | [`references/mutation-testing.md`](references/mutation-testing.md) |
| TDD のサイクル運用(Red→Green→Refactor、テストリスト先行) | [`references/tdd-cycle.md`](references/tdd-cycle.md) |
| TDD の Green 戦略(三角測量、仮実装/明白な実装) | [`references/tdd-green-strategy.md`](references/tdd-green-strategy.md) |
| テストの内部構成(AAA、Given-When-Then、テーブル駆動) | [`references/test-structure-anatomy.md`](references/test-structure-anatomy.md) |
| テストのライフサイクルとデータ供給(Four-Phase、Test Data Builder/Object Mother) | [`references/test-structure-lifecycle.md`](references/test-structure-lifecycle.md) |
| 良い単体テストの基本規範(4本柱、学派、観察可能な振る舞い、検証スタイル) | [`references/good-test-principles.md`](references/good-test-principles.md) |
| 脆さを避けるテスト設計(脆さの回避、モック濫用) | [`references/test-design-quality.md`](references/test-design-quality.md) |
| テスト対象側の設計と配置(Humble Object、四象限、事前条件・事後条件による境界) | [`references/test-target-design.md`](references/test-target-design.md) |
| テストダブルの使い分け(ダミー/スタブ/モック/スパイ/フェイク、Testcontainers) | [`references/test-doubles.md`](references/test-doubles.md) |
| テストが flaky・値の非決定性(時刻/乱数・UUID/浮動小数) | [`references/flakiness-value.md`](references/flakiness-value.md) |
| テストが flaky・協調の非決定性(並行・競合/テスト間順序・状態漏れ、検出と隔離の総論) | [`references/flakiness-concurrency.md`](references/flakiness-concurrency.md) |
| テストが flaky・外部依存と実時間(外部ネットワーク、タイマー・sleep) | [`references/flakiness-external.md`](references/flakiness-external.md) |
| 期待値が用意しにくい・性質で縛る(PBT、コンビナトリアル) | [`references/generative-property.md`](references/generative-property.md) |
| 期待値が用意しにくい・頑健性の生成系(ファジング、カバレッジガイド付きファジング) | [`references/generative-fuzzing.md`](references/generative-fuzzing.md) |
| 期待値が用意しにくい・過去出力基準(ゴールデン/スナップショット、承認、仕様化テスト) | [`references/oracle-past-output.md`](references/oracle-past-output.md) |
| 期待値が用意しにくい・別実装基準(参照実装・旧実装との差分テスト) | [`references/oracle-differential.md`](references/oracle-differential.md) |
| 期待値が用意しにくい・関係/形式手法(メタモルフィック、形式検証連携) | [`references/oracle-relational.md`](references/oracle-relational.md) |
| 期待値が用意しにくい・抽象モデル基準(モデルベーステスト) | [`references/oracle-model-based.md`](references/oracle-model-based.md) |
| 出力が非決定的(LLM/生成モデルを組み込んだシステム、揺らぎを層で封じ込める) | [`references/ai-nondeterministic.md`](references/ai-nondeterministic.md) |
| AI/LLM にテストを書かせる・レビューさせる(信頼は限定的、観点出しの叩き台、指摘の偽陽性対策) | [`references/ai-nondeterministic.md`](references/ai-nondeterministic.md) |
| 非機能・測定系(性能、負荷、ストレス、スパイク、ソーク、スケーラビリティ、キャパシティ) | [`references/nonfunctional-perf.md`](references/nonfunctional-perf.md) |
| 非機能・品質保証系(セキュリティ、a11y、互換、i18n、信頼性、可用性、カオス、contract) | [`references/nonfunctional-attributes.md`](references/nonfunctional-attributes.md) |
| 非機能・耐障害性とデータ整合(バルクヘッド/レートリミット/サーキットブレーカ、マイグレーション整合) | [`references/nonfunctional-resilience.md`](references/nonfunctional-resilience.md) |
| プロセス運用・静的・並行(BDD/ATDD、CI ゲート、カナリア、静的解析、冪等性、並行性) | [`references/process-static.md`](references/process-static.md) |
| テスト実装を複数 subagent に並列で投げる | [`../_shared/parallel-delegation.md`](../_shared/parallel-delegation.md) |
| コード/テスト/コミット/コメントのどこに何を書くか(How/What/Why/Why not) | [`../_shared/code-comment-commit-roles.md`](../_shared/code-comment-commit-roles.md) |

各 reference は手法ごとに **概要 / 目的といつ使うか / TypeScript example / 落とし穴** を厳密に定義している。
example をそのまま雛形にして対象へ写す。

## 割り当てのゲート

**手法を割り当てたら、その reference を必ず開いてから台帳の手法欄を埋める。** 手法欄には「手法名 + 参照した reference ファイル名」を書く。reference を開かず手法名だけ書くのは割り当て未完とみなす(自己流の example を書いて落とし穴を踏む逃げを塞ぐ)。

## やらないこと

- **reference を全部読まない。** 割り当てた手法のファイルだけ開く(progressive disclosure)。
- **手法名だけ書いて reference を読まずに実装しない。** 割り当ては reference 開封とセット。
- **カバレッジ率を目的化しない。** 高 C0/C1 は「到達」を示すだけで「検証」を保証しない。テストの強さは mutation([`references/mutation-testing.md`](references/mutation-testing.md))で点検する。
- **モックを濫用しない。** 実装詳細に結合したテストは脆い([`references/test-design-quality.md`](references/test-design-quality.md))。

## 次の工程

全 T-ID に手法(+ reference ファイル名)が割り当たったら、**test-verify** スキルで実装への橋渡しと実行ゲートへ進む。
