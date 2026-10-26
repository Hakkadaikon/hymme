---
name: test-design
description: テスト設計と既存テストレビューの入口。テストすべき振る舞いを網羅抽出し、手法を選び、実装と回帰へ渡す。「テスト設計」「テストケースを洗い出して」「テスト観点」「どうテストする」「テスト戦略」「テストが甘い/脆い/flaky」と言われたとき、テスト手法名(境界値、property based、mutation 等)が出たときに使う。TDD のサイクルは superpowers:test-driven-development。
user-invocable: true
argument-hint: "[テスト設計/レビューの対象(機能・ファイル・PR 差分)]"
---

# Test Design (テスト設計とレビューの入口)

対象から「テストすべき振る舞い」を出し切り、各振る舞いに手法を割り当て、実装と回帰へ橋渡しする。
工程は 3 スキルに分かれており、**必要な工程のスキルだけを読む**。工程スキルは Skill ツールの一覧に出していないので、`${CLAUDE_PLUGIN_ROOT}/skills/<工程名>/SKILL.md` を Read して従う。

役割分担(無理に結線しない、YAGNI):
- **テスト項目の抽出と手法選定**: このスキル系(test-extract / test-catalog / test-verify)
- **TDD サイクル(Red→Green→Refactor)**: superpowers:test-driven-development(implementer が実行)。hymme は「何をテストするか」(抽出・選定・検証)だけを担う
- **設計の網羅検査(状態遷移、並行、プロトコル)**: `loop-engineering`(TLA+)
- **実装の数学的証明(critical なアルゴリズムや性質)**: `formal-verification`(Lean 4)

## 使うとき / 使わないとき

- **使う**: 機能/モジュール/API のテスト項目を実装前に洗い出す。PR 差分や既存テストの抜け・脆さをレビューする。テスト手法(同値分割/PBT/E2E…)の選定。カバレッジやテストの強さ(mutation)の点検。
- **使わない**: 自明な1行や設定値のテスト、手法が自明で迷いがない小変更(YAGNI)。

## 工程(各工程は専用スキルへ委譲)

| 順 | スキル | やること | 出口条件 |
| --- | --- | --- | --- |
| 1 | **test-extract** | テストすべき振る舞いを T-ID 採番台帳(`tasks/test-design/<対象名>.md`)へ網羅抽出。レビュー時は既存テストを右側に埋めて両向きに読む | 全 `T-ID` が `[x]`(直し待ちの `[~]` は test-extract 手順5の例外)・欠番なし・機械確認の証跡提示 |
| 2 | **test-catalog** | 各 T-ID に手法を割り当て、その手法の reference だけを開く | 全 T-ID に「手法名 + reference ファイル名」が埋まる |
| 3 | **test-verify** | plan の Task(executing-plans か SDD implementer の TDD)または実装する本人へ橋渡し。実行ゲート(superpowers:verification-before-completion + 網羅逆引き・カバレッジ・flaky・mutation)→ 回帰として CI に固定 | 全 T-ID が実行ログの緑に対応し、CI に載る |

前段の出口条件を満たさず次へ進まない(各スキルが前提として検査する)。
手法の単発質問(「ペアワイズって何」等)は台帳なしで **test-catalog** の索引だけ引いてよい。

## superpowers ワークフロー上の位置

- **spec 承認後、superpowers:writing-plans の前(または並走)**に test-extract → test-catalog を回す。plan の各 Task の「Step 1: Write the failing test」は T-ID 台帳と `.feature` シナリオ**から**書く。Bounded パス(spec も plan も無い)では設計承認直後に同じ 0段→手法選定を回し、実装する本人のテストリストにする。
- **トレーサビリティは台帳の「テスト」列だけが持つ。** 列には plan に書いたテスト名(`it`/`test` 名)を入れる。plan・コード・コミットに `T-xxx` や手法名は書かない([`../_shared/stealth-artifacts.md`](../_shared/stealth-artifacts.md))。台帳は作業 worktree の `tasks/test-design/` に置き(worktree 作成前に作った台帳は SDD Setup 直後に worktree へコピー)、ブランチ完了後は残さない。
- **実行は superpowers:executing-plans(既定)か superpowers:subagent-driven-development。** 実装する本人(本体か implementer)が Task ごとに superpowers:test-driven-development で消化する。SDD の implementer は台帳を編集しない。`test-design-extract-gate` hook は implementer のテストファイル Write/Edit にも効く: 台帳が閉じていなければ機械的にブロックされ implementer は BLOCKED を返すので、コントローラが台帳を閉じてから再 dispatch する(意図した安全網)。
- **`hymme:verification-reviewer`(対象 `test-design`) はコントローラが dispatch する**: 0段を閉じた直後(plan にテストを書く前)と、最終 whole-branch レビューの前。

## 完了前の必須ゲート(コンプライアンスレビュー)

2 点でコントローラが `hymme:verification-reviewer`(対象 `test-design`) サブエージェントを dispatch して外側から検査させる: 合格が返るまでの往復の運用は [`../_shared/reviewer-loop.md`](../_shared/reviewer-loop.md)。

1. **0 段を閉じた直後**(plan の Task に失敗テストを書く前。単発なら テストを1件でも書く前): 台帳の未完・欠番、理由なしの優先度落としを検査。
2. **完了扱いにする前**: 手法名のみで reference 未開封、T-ID とテストの存在不一致、実行ログ無しの「緑」報告を検査。

レビュアーが挙げた違反を解消してから先へ進む。「緑と報告された」を証跡の代わりにしない。

## やらないこと

- 0段の飛ばし・reference の全読み・「緑」報告のみでの完了・台帳の後付け・スコープの自己縮小・異常系の実質スキップをしない(詳細は各工程スキルの「やらないこと」)。
- 自明な1行や設定値にテストを先行させない(YAGNI)。
- 台帳は `tasks/test-design/` 配下・git 管理外。`T-xxx` を本体へ漏らさない([`../_shared/stealth-artifacts.md`](../_shared/stealth-artifacts.md))。
