---
name: using-hymme
disable-model-invocation: true
description: セッション開始時、および superpowers の brainstorming / writing-plans / subagent-driven-development / systematic-debugging / finishing-a-development-branch に入る直前に使う。hymme の検証スキル・ワークフロースキル・agents を superpowers の各工程のどこで呼ぶか、hymme と superpowers のどちらが担当かを判断するときに参照する。
---

<SUBAGENT-STOP>
特定タスクの実行のために dispatch されたサブエージェントなら、このスキルは無視する。
</SUBAGENT-STOP>

# hymme は superpowers の上に載る

工程は superpowers が決める。hymme は各工程に検証 3 系統(loop-engineering / test-design / formal-verification)と git・レビュー運用を差し込む。スキルは Skill ツールで `superpowers:<name>` / `hymme:<name>`、agents は subagent_type `hymme:<name>` で呼ぶ。

## 差し込み地図

- **設計中**(`superpowers:brainstorming` の Size the Work が project で、The Written Design を書く前): 状態遷移・並行・順序があり有限化できる → `hymme:loop-engineering`(0→3段)。どんな入力でも成り立つべき判定(ルール・設定・条件式)→ 同スキルの SMT 経路。形式検証(SMT・TLA+・実ログ突き合わせ・Lean)の入口の前に `hymme:verifiability`(hook が強制)。critical なアルゴリズム・セキュリティ性質 → `hymme:formal-verification` の性質カタログ。成果は手法名なしの要件・受け入れ条件として spec へ。
- **spec 承認後〜`superpowers:writing-plans`**: `hymme:test-design`(test-extract → test-catalog)。brainstorming の「承認後は writing-plans だけ」は test-design を締め出さない。writing-plans の前に回す。plan の失敗テストは T-ID 台帳と Gherkin から書く。ID・手法名は plan に出さない。
- **実行**: 既定は `superpowers:executing-plans`(writing-plans の handoff では Native)+ `superpowers:test-driven-development`。ユーザーが SDD を指定しない限り、inline を選んだものとして扱い、plan の header や handoff の「SDD (recommended)」はこの既定で読み替える。`superpowers:subagent-driven-development` に切り替えるのは、タスクごとの探索やログで本体の文脈が膨らみ判断が鈍ると見込めるときだけ(`_shared/parallel-delegation.md` の委任の条件)。SDD の implementer は原則 `hymme:coder`。変更したコードの行・分岐カバレッジ 100% をテスト側から満たす(`${CLAUDE_PLUGIN_ROOT}/skills/tdd-cycle/SKILL.md` を Read)。plan の Commit ステップは実装する本人が `hymme:micro-commit` で実行する。証明・モデル検査は `hymme:prover` / `hymme:modeler` へ、完了前の検査は `hymme:verification-reviewer` へ、本体(SDD なら controller)が dispatch する。subagent を足す前と、作業を並列に配る前は `${CLAUDE_PLUGIN_ROOT}/skills/_shared/parallel-delegation.md`(委任するかの判断・ゲートの二段化・並列の数・事故の予防)。
- **完了前**: `superpowers:verification-before-completion` + test-verify(`hymme:test-design` の工程)の実行ゲート(カバレッジ 100% の計測を含む)。
- **コミット**: `hymme:micro-commit`。粒度判断は `hymme:commit-flow`。
- **レビュー**: superpowers の final review(SDD なら task review も)が基底。多観点は `hymme:diff-review`。PR 前は diff-review 必須(hook が `gh pr create` を止める)。
- **PR 作成**: `superpowers:finishing-a-development-branch` の選択肢 2 は、finishing の push を実行せずに `hymme:pr-create` へ入る。
- **バグ**: `superpowers:systematic-debugging` が基底。`hymme:gh-ci-investigate` と flakiness-*(`${CLAUDE_PLUGIN_ROOT}/skills/flakiness-<種別>/SKILL.md` を Read)は Phase 1 の道具。
- **訂正**: `superpowers:receiving-code-review` → `hymme:review-feedback`(水平展開・lessons)。
- **台帳**: `hymme:ledger-flow`。plan 実行の ledger(executing-plans / SDD 共通)は superpowers 形式のまま。
- **履歴破壊**: `hymme:rebase-flow` / `hymme:reset-flow`(git-guard hook が arm なしを止める)。

`hymme:verification-reviewer` は合格が返るまで往復させる(運用は `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reviewer-loop.md`)。
