---
name: using-hymme
description: セッション開始時、および superpowers の brainstorming / writing-plans / subagent-driven-development / systematic-debugging / finishing-a-development-branch に入る直前に使う。hymme の検証スキル・ワークフロースキル・agents を superpowers の各工程のどこで呼ぶか、hymme と superpowers のどちらが担当かを判断するときに参照する。
---

<SUBAGENT-STOP>
特定タスクの実行のために dispatch されたサブエージェントなら、このスキルは無視する。
</SUBAGENT-STOP>

# hymme は superpowers の上に載る

工程は superpowers が決める。hymme は各工程に検証 3 系統(loop-engineering / test-design / formal-verification)と git・レビュー運用を差し込む。スキルは Skill ツールで `superpowers:<name>` / `hymme:<name>`、agents は subagent_type `hymme:<name>` で呼ぶ。

## 差し込み地図

- **設計中**(`superpowers:brainstorming` の Architectural、spec 確定前): 状態遷移・並行・順序があり有限化できる → `hymme:loop-engineering`(0→3段)。critical なアルゴリズム・セキュリティ性質 → `hymme:formal-verification` の性質カタログ。成果は手法名なしの要件・受け入れ条件として spec へ。
- **spec 承認後〜`superpowers:writing-plans`**: `hymme:test-design`(test-extract → test-catalog)。plan の失敗テストは T-ID 台帳と Gherkin から書く。ID・手法名は plan に出さない。
- **実行**(`superpowers:subagent-driven-development`): implementer は原則 `hymme:coder`(superpowers 既定も可)+ `superpowers:test-driven-development`。証明・モデル検査は controller が `hymme:prover` / `hymme:modeler` を別 dispatch。`hymme:*-reviewer` も controller が dispatch。
- **完了前**: `superpowers:verification-before-completion` + `hymme:test-verify` の実行ゲート。
- **コミット**: `hymme:micro-commit`。粒度判断は `hymme:commit-flow`。
- **レビュー**: superpowers の task / final review が基底。多観点は `hymme:diff-review`。PR 前は diff-review 必須(hook が `gh pr create` を止める)。
- **PR 作成**: `superpowers:finishing-a-development-branch` → `hymme:pr-create`。
- **バグ**: `superpowers:systematic-debugging` が基底。`hymme:gh-ci-investigate` / flakiness-* は Phase 1 の道具。
- **訂正**: `superpowers:receiving-code-review` → `hymme:review-feedback`(水平展開・lessons)。
- **台帳**: `hymme:ledger-flow`。SDD の ledger は superpowers 形式のまま。
- **履歴破壊**: `hymme:rebase-flow` / `hymme:reset-flow`(git-guard hook が arm なしを止める)。

優先順位は、ユーザー指示(CLAUDE.md・直接の依頼)> スキル > 既定動作。

## `hymme:*-reviewer` の往復ループ

`hymme:*-reviewer`(loop-engineering-reviewer / test-design-reviewer / formal-verification-reviewer 等)は
一度呼んで終わりにしない。**指摘がなくなるまで「reviewer を呼ぶ→指摘を直す→再度 reviewer を呼ぶ」を繰り返す**
のが既定の運用(ユーザーが明示的に1回のレビューだけでよいと言わない限り)。

- reviewer の出力が本質的指摘(安全性・到達性・網羅性に影響するもの)と、ドキュメント間の記述不一致・
  言い回しのような瑣末な指摘を区別して返す場合、ループの終了条件は**本質的指摘が0件になった時点**
  とし、瑣末な指摘だけが残る状態は「合格、残課題あり」として次工程へ進んでよい(reviewer 自身が
  この区別をする前提は各 `*-reviewer` の定義を見る。無ければ reviewer に区別させるよう依頼文へ書く)。
- 1 往復で reviewer から複数の指摘が出る見込みがあるときは、reviewer に**見つけた指摘を一度の報告で
  まとめて全部出すよう明示的に依頼する**。1件直して再度呼ぶ→また1件出る、を繰り返すと往復が
  不必要に長引く。
- 往復のたびに新しい記録ファイル(判定表・経緯メモ等)を増やすと、その記録ファイル同士の整合性が
  新たな指摘の種になり、ループが本質と無関係な理由で伸びることがある。生成物を増やす判断は
  本当に必要な場合に限り、既存ファイルへの追記で済むなら増やさない。
