---
name: test-catalog
description: >
  test-design の手法選定工程。テスト手法カタログ(個別スキル 40 本)への索引と、
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
**このスキルは索引専用**。全手法の定義、目的、TypeScript example は下表の各技法スキルに厳密に置き、
**割り当てた手法のスキルだけを開く**(全部は開かない)。
各技法スキルは `disable-model-invocation: true` を持ち、ユーザーの自然な発話だけでは自動発動しない。
このスキルが索引から選んで明示的に参照することで初めて読まれる設計になっている。
迷ったら、まず種別(正常系、境界、異常系、非機能)から下表で当たりをつける。

**前提**: T-ID 台帳があること。無ければ **test-extract** へ戻る(手法の単発質問は索引だけで可)。

## 索引

| 何を検証したいか | 開くスキル |
| --- | --- |
| なぜその技法が要るか迷ったとき(テストの7原則) | [`../testing-principles/SKILL.md`](../testing-principles/SKILL.md) |
| 粒度の選択(サービス内部: unit/integration) | [`../levels/SKILL.md`](../levels/SKILL.md) |
| 粒度の選択(サービス間: component/contract/スキーマ検証) | [`../levels-service/SKILL.md`](../levels-service/SKILL.md) |
| 粒度の選択(システム全体・広域: system/E2E/UAT) | [`../levels-system/SKILL.md`](../levels-system/SKILL.md) |
| 粒度の選択(システム全体・運用: smoke/sanity/regression) | [`../levels-operational/SKILL.md`](../levels-operational/SKILL.md) |
| テスト戦略・配分(ピラミッド/トロフィー、関心事の階層化、リスクベース) | [`../strategy-allocation/SKILL.md`](../strategy-allocation/SKILL.md) |
| テスト戦略・運用(シフトレフト/ライト、環境・データ戦略、フレーキー方針、CI ゲーティング) | [`../strategy-operations/SKILL.md`](../strategy-operations/SKILL.md) |
| 仕様から導く・入力空間の分割(同値分割、境界値、ドメイン分析、デシジョンテーブル) | [`../blackbox-partition/SKILL.md`](../blackbox-partition/SKILL.md) |
| 仕様から導く・履歴と状態(状態遷移、CRUD/ライフサイクル、禁止仕様からの導出) | [`../blackbox-state/SKILL.md`](../blackbox-state/SKILL.md) |
| 条件の論理関係から組合せを縮約(原因結果グラフ、クラシフィケーションツリー) | [`../blackbox-cause-effect/SKILL.md`](../blackbox-cause-effect/SKILL.md) |
| 因子の被覆で組合せを縮約(ペアワイズ、直交表、T-way) | [`../blackbox-covering/SKILL.md`](../blackbox-covering/SKILL.md) |
| 経験・業務フローから導く(ユースケース、シナリオ、構文テスト) | [`../experience-scenario/SKILL.md`](../experience-scenario/SKILL.md) |
| 経験・過去バグをチェックリスト化して消し込む、壊れそうな入力を狙い撃つ(チェックリストベース、エラー推測) | [`../experience-checklist/SKILL.md`](../experience-checklist/SKILL.md) |
| 乱数や即興で揺さぶる、仕様が固まる前に触って調べる(ランダム/アドホックファジング、探索的、アドホック) | [`../experience-exploratory/SKILL.md`](../experience-exploratory/SKILL.md) |
| 構造網羅・制御フロー基本(C0/C1、条件、判定/条件) | [`../whitebox-controlflow-basic/SKILL.md`](../whitebox-controlflow-basic/SKILL.md) |
| 構造網羅・経路と独立影響(MC/DC、多重条件、パス、基底パス) | [`../whitebox-controlflow-path/SKILL.md`](../whitebox-controlflow-path/SKILL.md) |
| 構造網羅・ループとデータフロー(ループテスト、def-use) | [`../whitebox-dataflow-loop/SKILL.md`](../whitebox-dataflow-loop/SKILL.md) |
| テストの強さを測る(mutation、テストの欠陥検出力) | [`../mutation-testing/SKILL.md`](../mutation-testing/SKILL.md) |
| TDD のサイクル運用(Red→Green→Refactor、テストリスト先行) | [`../tdd-cycle/SKILL.md`](../tdd-cycle/SKILL.md) |
| TDD の Green 戦略(三角測量、仮実装/明白な実装) | [`../tdd-green-strategy/SKILL.md`](../tdd-green-strategy/SKILL.md) |
| テストの内部構成(AAA、Given-When-Then、テーブル駆動) | [`../test-structure-anatomy/SKILL.md`](../test-structure-anatomy/SKILL.md) |
| テストのライフサイクルとデータ供給(Four-Phase、Test Data Builder/Object Mother) | [`../test-structure-lifecycle/SKILL.md`](../test-structure-lifecycle/SKILL.md) |
| 良い単体テストの基本規範(4本柱、学派、観察可能な振る舞い、検証スタイル) | [`../good-test-principles/SKILL.md`](../good-test-principles/SKILL.md) |
| 脆さを避けるテスト設計(脆さの回避、モック濫用) | [`../test-design-quality/SKILL.md`](../test-design-quality/SKILL.md) |
| テスト対象側の設計と配置(Humble Object、四象限、事前条件・事後条件による境界) | [`../test-target-design/SKILL.md`](../test-target-design/SKILL.md) |
| テストダブルの使い分け(ダミー/スタブ/モック/スパイ/フェイク、Testcontainers) | [`../test-doubles/SKILL.md`](../test-doubles/SKILL.md) |
| テストが flaky・値の非決定性(時刻/乱数・UUID/浮動小数) | [`../flakiness-value/SKILL.md`](../flakiness-value/SKILL.md) |
| テストが flaky・協調の非決定性(並行・競合/テスト間順序・状態漏れ、検出と隔離の総論) | [`../flakiness-concurrency/SKILL.md`](../flakiness-concurrency/SKILL.md) |
| テストが flaky・外部依存と実時間(外部ネットワーク、タイマー・sleep) | [`../flakiness-external/SKILL.md`](../flakiness-external/SKILL.md) |
| 期待値が用意しにくい・性質で縛る(PBT、コンビナトリアル) | [`../generative-property/SKILL.md`](../generative-property/SKILL.md) |
| 期待値が用意しにくい・頑健性の生成系(ファジング、カバレッジガイド付きファジング) | [`../generative-fuzzing/SKILL.md`](../generative-fuzzing/SKILL.md) |
| 期待値が用意しにくい・過去出力基準(ゴールデン/スナップショット、承認、仕様化テスト) | [`../oracle-past-output/SKILL.md`](../oracle-past-output/SKILL.md) |
| 期待値が用意しにくい・別実装基準(参照実装・旧実装との差分テスト) | [`../oracle-differential/SKILL.md`](../oracle-differential/SKILL.md) |
| 期待値が用意しにくい・関係/形式手法(メタモルフィック、形式検証連携) | [`../oracle-relational/SKILL.md`](../oracle-relational/SKILL.md) |
| 期待値が用意しにくい・抽象モデル基準(モデルベーステスト) | [`../oracle-model-based/SKILL.md`](../oracle-model-based/SKILL.md) |
| 出力が非決定的(LLM/生成モデルを組み込んだシステム、揺らぎを層で封じ込める) | [`../ai-nondeterministic/SKILL.md`](../ai-nondeterministic/SKILL.md) |
| AI/LLM にテストを書かせる・レビューさせる(信頼は限定的、観点出しの叩き台、指摘の偽陽性対策) | [`../ai-nondeterministic/SKILL.md`](../ai-nondeterministic/SKILL.md) |
| 非機能・測定系(性能、負荷、ストレス、スパイク、ソーク、スケーラビリティ、キャパシティ) | [`../nonfunctional-perf/SKILL.md`](../nonfunctional-perf/SKILL.md) |
| 非機能・品質保証系(セキュリティ、a11y、互換、i18n、信頼性、可用性、カオス、contract) | [`../nonfunctional-attributes/SKILL.md`](../nonfunctional-attributes/SKILL.md) |
| 非機能・耐障害性とデータ整合(バルクヘッド/レートリミット/サーキットブレーカ、マイグレーション整合) | [`../nonfunctional-resilience/SKILL.md`](../nonfunctional-resilience/SKILL.md) |
| プロセス運用・静的・並行(BDD/ATDD、CI ゲート、カナリア、静的解析、冪等性、並行性) | [`../process-static/SKILL.md`](../process-static/SKILL.md) |
| テスト実装を複数 subagent に並列で投げる | [`../_shared/parallel-delegation.md`](../_shared/parallel-delegation.md) |
| コード/テスト/コミット/コメントのどこに何を書くか(How/What/Why/Why not) | [`../_shared/code-comment-commit-roles.md`](../_shared/code-comment-commit-roles.md) |

各技法スキルは手法ごとに **概要 / 目的といつ使うか / TypeScript example / 落とし穴** を厳密に定義している。
example をそのまま雛形にして対象へ写す。

## 割り当てのゲート

**手法を割り当てたら、そのスキルを必ず開いてから台帳の手法欄を埋める。** 手法欄には「手法名 + 参照したスキル名」を書く。スキルを開かず手法名だけ書くのは割り当て未完とみなす(自己流の example を書いて落とし穴を踏む逃げを塞ぐ)。

## やらないこと

- **技法スキルを全部開かない。** 割り当てた手法のスキルだけ開く(progressive disclosure)。
- **手法名だけ書いてスキルを開かずに実装しない。** 割り当てはスキル開封とセット。
- **カバレッジ率を目的化しない。** 高 C0/C1 は「到達」を示すだけで「検証」を保証しない。テストの強さは mutation([`../mutation-testing/SKILL.md`](../mutation-testing/SKILL.md))で点検する。
- **モックを濫用しない。** 実装詳細に結合したテストは脆い([`../test-design-quality/SKILL.md`](../test-design-quality/SKILL.md))。

## 次の工程

全 T-ID に手法(+ 参照したスキル名)が割り当たったら、**test-verify** スキルで実装への橋渡しと実行ゲートへ進む。
