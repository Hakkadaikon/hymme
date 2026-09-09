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
