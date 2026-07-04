---
name: test-design
description: >
  テストを設計する／既存テストをレビューするための手法カタログと選定ワークフロー。
  対象(機能、モジュール、API、PR 差分)から「テストすべき振る舞い」を網羅抽出し、
  各振る舞いに適切なテスト手法を割り当て、必要な reference だけを読みに行く。
  ユーザーが「テスト設計」「テストケースを洗い出す」「テスト観点」「テストレビュー」
  「どんなテストを書くべき」「どうテストする」「テストしにくい」「カバレッジ」「テスト戦略」
  「単体テストの考え方」「TDD」「テストファースト」と言ったとき、
  または「テストが甘い／薄い／足りない」「テストが脆い／壊れやすい／実装を変えると壊れる」
  「テストが flaky ／不安定／たまに落ちる」「リファクタ前にテストで固めたい」と困っているとき、
  あるいは手法名(同値分割、境界値、ドメイン分析、デシジョンテーブル、状態遷移、ペアワイズ、直交表、T-way、
  判定／条件網羅、MC/DC、基底パス、構文テスト、contract／Pact、property based、mutation、
  メタモルフィック、ゴールデン／承認、仕様化テスト、チェックリストベース、
  モック／スタブ／テストダブル、LLM・非決定的出力のテスト、EARS)を直接挙げたとき、
  実装前にテスト項目を固めたい／既存テストの抜けや脆さを点検したいときに使用する。
  実装の駆動は coder agent の TDD、設計の網羅検査は loop-engineering(TLA+)、実装の証明は formal-verification(Lean)。
---

# Test Design (テスト設計とレビュー支援)

テスト手法を網羅したカタログと、対象から適切な手法を選ぶワークフロー。
**SKILL.md は索引**。全手法の定義、目的、TypeScript example は `reference/` に厳密に置き、
**何を作る/レビューするかに応じて必要な reference だけを読みに行く**(全部は読まない)。

役割分担(無理に結線しない、YAGNI):
- **テスト項目の抽出と手法選定**：このスキル
- **実装の駆動(TDD: Red→Green→Refactor)**：`coder` agent
- **設計の網羅検査(状態遷移、並行、プロトコル)**：`loop-engineering`(TLA+)
- **実装の数学的証明(critical なアルゴリズムや性質)**：`formal-verification`(Lean 4)

## 使うとき / 使わないとき

| 使う | 使わない |
| --- | --- |
| 機能/モジュール/API のテスト項目を実装前に洗い出す | 自明な1行や設定値のテスト(YAGNI) |
| PR 差分や既存テストの抜け、脆さをレビューする | 手法が自明で迷いがない小変更 |
| どのテスト手法(同値分割/PBT/E2E…)が適切か選ぶ | (なし) |
| カバレッジやテストの強さ(mutation)を点検する | (なし) |

## ワークフロー

### 1. 対象を見て、テストすべき振る舞いを抽出する(0段)

**いきなりテストを書かない。** 対象から「テストすべき振る舞い」を網羅的に出し切る工程を先に置く。
ここは姉妹スキル `loop-engineering` の「0. 抽出ループ」を踏襲する。漏れはこの入口に落ちる。

原則は **過剰抽出は安全、漏れは危険**。迷ったら採り、後で優先度で落とす。

1. **曖昧な用語と暗黙の要求を先に定義する**：抽出の前に、対象に出てくる語の意味を一つずつ確定させる。「翌営業日」なら「営業日とは? 休日とは(日曜、指定土曜、祝日)? 月跨ぎは?」まで割る。語の定義が曖昧なまま振る舞いを出すと、境界(連休、月末)と異常系がそっくり抜ける。**用語の未定義は最大の抽出漏れ源**。併せて「当たり前要求」(セキュリティ、実行効率、法令)など暗黙のニーズも、非機能の種別として明示に引き上げる。
2. **走査アンカーを選ぶ**：対象の構造単位を決める。受け入れ条件、関数シグネチャ、コードの分岐、状態遷移、API エンドポイント×メソッド、不変条件のいずれかを使う。仕様視点(ブラックボックス)とコード視点(ホワイトボックス)で**独立に**出して union を取ると漏れにくい。
3. **採番チェックリスト台帳に落とす**：[`assets/test-extract-template.md`](assets/test-extract-template.md) を `tasks/test-design/<対象名>.md`(この場所に固定。`test-design-extract-gate` hook が検査する場所)にコピーし、振る舞いごとに `T-001` から連番で1行立てる。頭の中で済ませない。
4. **各振る舞いに種別を振る**：テンプレートの EARS 5類型ラベル(`event`/`state`/`ubiquitous`/`unwanted`/`optional`、境界は `boundary`、非機能は `nonfunctional`)のいずれかを振る。この型ラベルは loop-engineering の EARS と共通で、TLA+ を使わない通常のタスクでも「正常系に対応する異常系を出したか」を書式として強制する軽量版として使う。先に**事前条件**(対象が規定の振る舞いを保証する入力・状態の範囲)を確定させ、その内側だけを網羅対象にする。事前条件違反のうち**応答を保証したい分だけ**を事後条件へ引き上げて `unwanted` に積む(契約の詳細は [`reference/test-target-design.md`](reference/test-target-design.md))。そのうえで各 `event`/`state` 行に「不正入力なら? 境界なら? 並行なら?」を必ず問い、`unwanted` の行を系統的に生やす。履歴依存があるものは「**起きてはいけない振る舞い(禁止される列)**は何か」も問う。途中まで正常で一手で初めて禁止になる列(二重支払い、期限切れ後の操作)が、ここで `unwanted` の行になる(導出は [`reference/blackbox-state.md`](reference/blackbox-state.md) の禁止仕様からのテスト導出)。状態遷移・並行・プロトコルがあり TLA+ の網羅検査まで要る場合は `loop-engineering` へ委譲する(下記「実装/検証へ橋渡し」参照)。
5. **全 ID が `[x]` で欠番なしになったら抽出を閉じる**。未チェックが残る=抽出途中。
6. **閉じた証跡を出す(必須ゲート、自己申告で済ませない)**：テストを1件でも書く、または `coder` に渡す前に、台帳の絶対パスと、未チェック残数ゼロ・欠番なしを機械確認した出力を応答に示す。示せないなら0段は未完で、先へ進まない。
   ```sh
   grep -cE '^\| T-' <台帳>                  # 立てた T-ID の総数
   grep -E '^\| T-' <台帳> | grep -c '\[ \]'  # 未チェックの行数(0段を閉じる時点で 0)
   grep -nE '^\| T-' <台帳>                  # T 番号を目視で連番確認(欠番=抽出途中)
   ```

> レビュー用途のときは、既存テストを台帳の右側(テスト名)に先に埋める。台帳は両向きに読む。
> **左側(振る舞い)に空欄が残れば、それがテストの抜け**である。
> **右側(テスト)に対応する左側が無ければ、それは根拠を説明できないテスト**で、対象外の振る舞いを縛る脆さか、抽出漏れ(立て損ねた振る舞い)のどちらかを疑う。
> **手法が実装詳細に密結合していれば、それが脆さ**である。
> 右側に埋めたテストが **skip / pending でなく現に緑で走っているか**も確認する。台帳上は埋まっていても skip で黙殺されていれば、それは守られていないテストである([`reference/levels-operational.md`](reference/levels-operational.md) の skip 黙殺の罠)。
> **既存テストを全件転記したか**は、テストファイルから抽出した件数と右側の件数の一致で確かめる(読んで分かった気にならない)。

### 2. 各振る舞いに手法を割り当て、その reference だけ読む

抽出した各 `T-ID` に、どのテスト手法で検証するかを割り当てる。
**割り当てた手法が載っている reference だけを読む**(索引は下表)。
迷ったら、まず種別(正常系、境界、異常系、非機能)から下表で当たりをつける。

| 何を検証したいか | 読む reference |
| --- | --- |
| なぜその技法が要るか迷ったとき(テストの7原則) | [`reference/testing-principles.md`](reference/testing-principles.md) |
| 粒度の選択(サービス内部: unit/integration) | [`reference/levels.md`](reference/levels.md) |
| 粒度の選択(サービス間: component/contract/スキーマ検証) | [`reference/levels-service.md`](reference/levels-service.md) |
| 粒度の選択(システム全体・広域: system/E2E/UAT) | [`reference/levels-system.md`](reference/levels-system.md) |
| 粒度の選択(システム全体・運用: smoke/sanity/regression) | [`reference/levels-operational.md`](reference/levels-operational.md) |
| テスト戦略・配分(ピラミッド/トロフィー、関心事の階層化、リスクベース) | [`reference/strategy-allocation.md`](reference/strategy-allocation.md) |
| テスト戦略・運用(シフトレフト/ライト、環境・データ戦略、フレーキー方針、CI ゲーティング) | [`reference/strategy-operations.md`](reference/strategy-operations.md) |
| 仕様から導く・入力空間の分割(同値分割、境界値、ドメイン分析、デシジョンテーブル) | [`reference/blackbox-partition.md`](reference/blackbox-partition.md) |
| 仕様から導く・履歴と状態(状態遷移、CRUD/ライフサイクル、禁止仕様からの導出) | [`reference/blackbox-state.md`](reference/blackbox-state.md) |
| 条件の論理関係から組合せを縮約(原因結果グラフ、クラシフィケーションツリー) | [`reference/blackbox-cause-effect.md`](reference/blackbox-cause-effect.md) |
| 因子の被覆で組合せを縮約(ペアワイズ、直交表、T-way) | [`reference/blackbox-covering.md`](reference/blackbox-covering.md) |
| 経験・業務フローから導く(ユースケース、シナリオ、構文テスト) | [`reference/experience-scenario.md`](reference/experience-scenario.md) |
| 経験・ヒューリスティック(チェックリストベース、エラー推測、ランダム/アドホックファジング、探索的) | [`reference/experience-heuristic.md`](reference/experience-heuristic.md) |
| 構造網羅・制御フロー基本(C0/C1、条件、判定/条件) | [`reference/whitebox-controlflow-basic.md`](reference/whitebox-controlflow-basic.md) |
| 構造網羅・経路と独立影響(MC/DC、多重条件、パス、基底パス) | [`reference/whitebox-controlflow-path.md`](reference/whitebox-controlflow-path.md) |
| 構造網羅・ループとデータフロー(ループテスト、def-use) | [`reference/whitebox-dataflow-loop.md`](reference/whitebox-dataflow-loop.md) |
| テストの強さを測る(mutation、テストの欠陥検出力) | [`reference/mutation-testing.md`](reference/mutation-testing.md) |
| TDD のサイクル運用(Red→Green→Refactor、テストリスト先行) | [`reference/tdd-cycle.md`](reference/tdd-cycle.md) |
| TDD の Green 戦略(三角測量、仮実装/明白な実装) | [`reference/tdd-green-strategy.md`](reference/tdd-green-strategy.md) |
| テストの内部構成(AAA、Given-When-Then、テーブル駆動) | [`reference/test-structure-anatomy.md`](reference/test-structure-anatomy.md) |
| テストのライフサイクルとデータ供給(Four-Phase、Test Data Builder/Object Mother) | [`reference/test-structure-lifecycle.md`](reference/test-structure-lifecycle.md) |
| 良い単体テストの基本規範(4本柱、学派、観察可能な振る舞い、検証スタイル) | [`reference/good-test-principles.md`](reference/good-test-principles.md) |
| 脆さを避けるテスト設計(脆さの回避、モック濫用) | [`reference/test-design-quality.md`](reference/test-design-quality.md) |
| テスト対象側の設計と配置(Humble Object、四象限、事前条件・事後条件による境界) | [`reference/test-target-design.md`](reference/test-target-design.md) |
| テストダブルの使い分け(ダミー/スタブ/モック/スパイ/フェイク、Testcontainers) | [`reference/test-doubles.md`](reference/test-doubles.md) |
| テストが flaky・値の非決定性(時刻/乱数・UUID/浮動小数) | [`reference/flakiness-value.md`](reference/flakiness-value.md) |
| テストが flaky・協調の非決定性(並行・競合/テスト間順序・状態漏れ、検出と隔離の総論) | [`reference/flakiness-concurrency.md`](reference/flakiness-concurrency.md) |
| テストが flaky・外部依存と実時間(外部ネットワーク、タイマー・sleep) | [`reference/flakiness-external.md`](reference/flakiness-external.md) |
| 期待値が用意しにくい・性質で縛る(PBT、コンビナトリアル) | [`reference/generative-property.md`](reference/generative-property.md) |
| 期待値が用意しにくい・頑健性の生成系(ファジング、カバレッジガイド付きファジング) | [`reference/generative-fuzzing.md`](reference/generative-fuzzing.md) |
| 期待値が用意しにくい・過去出力/別実装基準(ゴールデン、承認、仕様化テスト、差分) | [`reference/oracle-snapshot.md`](reference/oracle-snapshot.md) |
| 期待値が用意しにくい・関係/形式手法(メタモルフィック、形式検証連携) | [`reference/oracle-relational.md`](reference/oracle-relational.md) |
| 期待値が用意しにくい・抽象モデル基準(モデルベーステスト) | [`reference/oracle-model-based.md`](reference/oracle-model-based.md) |
| 出力が非決定的(LLM/生成モデルを組み込んだシステム、揺らぎを層で封じ込める) | [`reference/ai-nondeterministic.md`](reference/ai-nondeterministic.md) |
| AI/LLM にテストを書かせる・レビューさせる(信頼は限定的、観点出しの叩き台、指摘の偽陽性対策) | [`reference/ai-nondeterministic.md`](reference/ai-nondeterministic.md) |
| 非機能・測定系(性能、負荷、ストレス、スパイク、ソーク、スケーラビリティ、キャパシティ) | [`reference/nonfunctional-perf.md`](reference/nonfunctional-perf.md) |
| 非機能・品質保証系(セキュリティ、a11y、互換、i18n、信頼性、可用性、カオス、contract) | [`reference/nonfunctional-attributes.md`](reference/nonfunctional-attributes.md) |
| 非機能・耐障害性とデータ整合(バルクヘッド/レートリミット/サーキットブレーカ、マイグレーション整合) | [`reference/nonfunctional-resilience.md`](reference/nonfunctional-resilience.md) |
| プロセス運用・静的・並行(BDD/ATDD、CI ゲート、カナリア、静的解析、冪等性、並行性) | [`reference/process-static.md`](reference/process-static.md) |
| テスト実装を複数 subagent に並列で投げる(共有リソースの直列化・命名衝突の予防・単体緑≠統合緑・成果物の実在で進捗判定・外部ツールの sandbox 可否) | [`../_shared/parallel-delegation.md`](../_shared/parallel-delegation.md) |
| コード/テスト/コミット/コメントのどこに何を書くか(How/What/Why/Why not の役割分担) | [`../_shared/code-comment-commit-roles.md`](../_shared/code-comment-commit-roles.md) |

各 reference は手法ごとに **概要 / 目的といつ使うか / TypeScript example / 落とし穴** を厳密に定義している。
example をそのまま雛形にして対象へ写す。

**手法を割り当てたら、その reference を必ず開いてから台帳の手法欄を埋める。** 手法欄には「手法名 + 参照した reference ファイル名」を書く。reference を開かず手法名だけ書くのは割り当て未完とみなす(自己流の example を書いて落とし穴を踏む逃げを塞ぐ)。

### 3. 実装/検証へ橋渡しする

割り当てが済んだら、台帳のトレーサビリティマトリクス(振る舞い→手法→テスト名)を満たすよう実装側へ渡す。

- **実装の駆動**：テスト項目リストを `coder` agent に渡し、t-wada スタイルの TDD(Red→Green→Refactor)で1項目ずつ消化する。台帳の `T-ID` リストがそのままテストリストになる。
- **設計に状態遷移、並行、順序があるとき**：テストで全 interleaving は踏めない。`loop-engineering`(TLA+)で設計をモデル検査し、反例を Gherkin の受け入れシナリオに落としてから、その述語をテストへ移す。
- **critical なアルゴリズムやセキュリティ性質**：通常テストより強い保証が要るなら `formal-verification`(Lean 4)で証明し、証明済み述語を property-based test(`generative-property.md`)の property として叩く。
- **実行ゲート(自己申告を信用しない)**：実装が済んだら、テストを実際に走らせ、生ログを自分で確認するまで完了扱いにしない。「全テスト緑、型も問題なし」という agent の報告だけで閉じると、flaky や型エラーが残ったまま通過する(委譲先がそう報告して実際は赤だった実例がある)。次を確認し、**実行コマンドと生出力(終了コード、緑赤の集計行)を応答に貼る**。貼れないなら未完。
  1. **網羅(取りこぼし無し)**：台帳の全 `T-ID` について、対応するテスト名が実在のテストファイル内に見つかることを grep で1行ずつ逆引きする。緑チェックはスイートの健全性を見るだけで、coder が一部 `T-ID` を実装し忘れても「全緑」になる。存在チェックは緑チェックと別物として必ず回す。
  2. **緑**：全テストが緑。型検査がクリーン。
  3. **flaky**:性質ベースやメタモルフィック、並行を含むテストは seed を変えて複数回(最低でも数十回、または CI の連続成功)走っても落ちない。1回の緑では flaky は見えない。
  4. **強さ(critical のみ)**:金額、セキュリティ、状態遷移など critical な `T-ID` は、緑に加えて mutation([`reference/mutation-testing.md`](reference/mutation-testing.md))を回し、survived がアサーション不足として残っていないことを確認する。全部に回すのは過剰(YAGNI)。
  - 台帳の `T-ID` は、貼ったログ中の該当テスト名の緑に対応して初めて閉じる。

### 4. 緑にしたテストを回帰として固定する(守られ続ける状態へ渡す)

実行ゲートを通った緑は、その場限りでは守られ続けない。次の変更で黙って赤化しないよう継続実行に載せて初めて「テストが守られる」状態になる。

- 緑にしたテスト群を CI の継続実行対象に入れる([`reference/process-static.md`](reference/process-static.md) の CI 自動実行)。
- critical な `T-ID` は mutation やカバレッジを CI ゲートにし、下限を割る変更をマージさせない([`reference/process-static.md`](reference/process-static.md)、[`reference/mutation-testing.md`](reference/mutation-testing.md))。
- 以後バグが出たら、その欠陥を再現する最小テストを1本固定して回帰へ積む([`reference/levels-operational.md`](reference/levels-operational.md) の回帰テスト)。台帳には新しい `T-ID` として追記する。

## 完了前の必須ゲート(コンプライアンスレビュー)

テストを1件でも書く前(0段を閉じた直後)と、実装が済んで完了扱いにする前の2点で、必ず `hymme:test-design-reviewer` サブエージェントへ渡して外側から検査させる。
渡すもの: T-ID 台帳のパス、テストファイルと実行ログの場所。
レビュアーが挙げた違反(台帳の未完・欠番、手法名のみで reference 未開封、T-ID とテストの存在不一致、実行ログ無しの「緑」報告、理由なしの優先度落とし)を解消してから先へ進む。「緑と報告された」を証跡の代わりにしない。

## やらないこと

- **0段(振る舞い抽出)を飛ばしてテストを書かない。** 思いつきで書くと正常系に偏り、境界と異常系が抜ける。
- **reference を全部読まない。** 割り当てた手法のファイルだけ開く(progressive disclosure)。
- **カバレッジ率を目的化しない。** 高 C0/C1 は「到達」を示すだけで「検証」を保証しない。テストの強さは mutation(`mutation-testing.md`)で点検する。
- **モックを濫用しない。** 実装詳細に結合したテストは脆い。詳細は `test-design-quality.md`。
- **「緑」の報告だけで完了にしない。** 実行ログと型検査を自分で確認する(上の実行ゲート)。flaky は1回の緑では見えないので、揺らぎを含むテストは複数回回す。flaky の要因別の検出と封じ込めは、値の非決定性([`reference/flakiness-value.md`](reference/flakiness-value.md))と協調の非決定性([`reference/flakiness-concurrency.md`](reference/flakiness-concurrency.md))に体系化してある。
- **API 境界の互換性維持を抜かさない。** 提供側と利用側を別々にテストするだけでは破壊的変更を見逃す。consumer-driven contract([`reference/nonfunctional-attributes.md`](reference/nonfunctional-attributes.md) のコントラクトテスト、粒度の選択は [`reference/levels.md`](reference/levels.md))で境界の互換を固定する。
- **台帳を実装後に後付けで埋めない。** 0段は実装の前に閉じる。後から辻褄を合わせると、書いたテストに台帳を寄せるだけになり抜けが見えなくなる。
- **手法名だけ書いて reference を読まずに実装しない。** 割り当ては reference 開封とセット(上の手法割り当て)。
- **異常系や境界を安易に「優先度低/対象外」へ流して実質スキップしない。** 過剰抽出の趣旨は「出してから落とす」であって、出さない言い訳ではない。落とすなら台帳に理由を1行残す。
- **「巨大だから別タスク」と振る舞いのスコープを自分で縮めない。** 依存先の仕様も調べて台帳に積む。大きい対象は MECE 分割して順に消化し、分割をスコープ除外と混同しない。完了条件は「対象範囲の全 T-ID が緑か、物理的に止まるまで」で、自発的な区切りを完了と偽らない(異常系・境界を安易に「対象外」へ流さない、の延長)。
- 自明な1行や設定値にテストを先行させない(YAGNI)。
