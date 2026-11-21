---
name: using-hymme
disable-model-invocation: true
description: SessionStart hook が毎セッション注入する地図。hymme の検証スキル・ワークフロースキル・agents を superpowers の各工程のどこで使うか、superpowers と食い違うときにどちらに従うかを示す。モデルからは呼ばない。
---

<SUBAGENT-STOP>
特定タスクの実行のために dispatch されたサブエージェントなら、このスキルは無視する。
</SUBAGENT-STOP>

# hymme は superpowers の上に載る

工程は superpowers が決める。hymme は各工程に検証 3 系統(loop-engineering / test-design / formal-verification)と git・レビュー運用を差し込む。スキルは Skill ツールで `superpowers:<name>` / `hymme:<name>`、agents は subagent_type `hymme:<name>` で呼ぶ。

## 差し込み地図

- **設計中**(`superpowers:brainstorming` の Size the Work が project で、The Written Design を書く前): 状態遷移・並行・順序があり有限化できる → `hymme:loop-engineering`(0→3段)。どんな入力でも成り立つべき判定(ルール・設定・条件式)→ 同スキルの SMT 経路。形式検証(SMT・TLA+・実ログ突き合わせ・Lean)の入口の前に `hymme:verifiability`(hook が強制)。critical なアルゴリズム・セキュリティ性質 → `hymme:formal-verification` の性質カタログ。成果は手法名なしの要件・受け入れ条件として spec へ。検証の入口の前に、何を実証するかの一覧をユーザーが承認する(`hymme claims request <名前>`。承認が無ければ hook が止める。ユーザーと対話できないサブエージェントは BLOCKED で返す)。
- **spec 承認後〜`superpowers:writing-plans`**: `hymme:test-design`(test-extract → test-catalog)。brainstorming の「承認後は writing-plans だけ」は test-design を締め出さない。writing-plans の前に回す。plan の失敗テストは T-ID 台帳と Gherkin から書く。ID・手法名は plan に出さない。
- **実行**: 既定は `superpowers:executing-plans`(writing-plans の handoff では Native)+ `superpowers:test-driven-development`。ユーザーが SDD を指定しない限り、inline を選んだものとして扱い、plan の header や handoff の「SDD (recommended)」はこの既定で読み替える。`superpowers:subagent-driven-development` に切り替えるのは、タスクごとの探索やログで本体の文脈が膨らみ判断が鈍ると見込めるときだけ(`${CLAUDE_PLUGIN_ROOT}/skills/_shared/parallel-delegation.md` の委任の条件)。SDD の implementer は superpowers 既定で、controller は implementer の brief に `${CLAUDE_PLUGIN_ROOT}/skills/tdd-cycle/SKILL.md`(カバレッジと予防規範)を読むことと、Commit を `hymme:micro-commit` で行うことを書く。変更したコードの行・分岐カバレッジ 100% をテスト側から満たす(`${CLAUDE_PLUGIN_ROOT}/skills/tdd-cycle/SKILL.md` を Read。実装中の予防規範も同じファイル)。plan の Commit ステップは実装する本人が `hymme:micro-commit` で実行する。証明・モデル検査は `hymme:prover` / `hymme:modeler` へ、完了前の検査は `hymme:verification-reviewer` へ、本体(SDD なら controller)が dispatch する。subagent を足す前と、作業を並列に配る前は `${CLAUDE_PLUGIN_ROOT}/skills/_shared/parallel-delegation.md`(委任するかの判断・ゲートの二段化・並列の数・事故の予防)。
- **完了前**: `superpowers:verification-before-completion` + test-verify(`hymme:test-design` の工程)の実行ゲート(カバレッジ 100% の計測を含む)。実システムで動かして確かめる(`hymme:real-surface` の定義 `tasks/surface.md` の確認のコマンド)。spec のある設計は実ログを突き合わせる(loopeng-tracecheck)。
- **コミット**: `hymme:micro-commit`。粒度判断は `hymme:commit-flow`。
- **レビュー**: superpowers の final review(SDD なら task review も)が基底。多観点は `hymme:diff-review`。変更がブランチの外へ出る前(PR・MR の作成、既定ブランチへの merge、PR 作成後の push)は diff-review 必須で、hook が下の「統合の入口」の条件を確かめる。
- **PR 作成**: `superpowers:finishing-a-development-branch` の選択肢 2 は、finishing の push を実行せずに `hymme:pr-create` へ入る。
- **バグ**: `superpowers:systematic-debugging` が基底。`hymme:gh-ci-investigate` と flakiness-*(`${CLAUDE_PLUGIN_ROOT}/skills/flakiness-<種別>/SKILL.md` を Read)は Phase 1 のツール。後段(結合・e2e・実ログ・CI・本番)で見つかった欠陥と、報告されたバグは `hymme:escape-flow`。実システムで再現し、拾えたはずの前の段にテストを足すまで、変更は統合できない。
- **訂正**: `superpowers:receiving-code-review` → `hymme:review-feedback`(水平展開・lessons)。
- **台帳**: `hymme:ledger-flow`。plan 実行の ledger(executing-plans / SDD 共通)は superpowers 形式のまま。
- **履歴破壊**: `hymme:rebase-flow` / `hymme:reset-flow`(git-guard hook が arm なしを止める)。

`hymme:verification-reviewer` は合格が返るまで往復させる(運用は `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reviewer-loop.md`)。

## 強制のしくみ

検査が読むのは hook が書いた署名つきの記録だけで、台帳に自分で付けたチェックは合格の根拠にならない。記録は git の共通ディレクトリに置かれ、別の worktree からも同じものが見える。記録の置き場と署名の鍵には触れない(hook が止める)。

- **ユーザーの承認**: 申請は `hymme claims request` / `hymme chart request` / `hymme exception request` / `hymme escape unreachable`。hook が申請の中身をユーザーに表示し、ユーザーが `承認 <承認コード>` とだけ入力すると記録される。エージェントは承認を入力できない。
- **reviewer の判定**: reviewer が返ったときに hook が最後のメッセージから記録する。`hymme:verification-reviewer` は `判定: 合格 対象=<系統> 名前=<名前>`、`hymme:diff-reviewer` は `must:` `lenses:` `claim_only:` の3行。
- **実行の記録**: 検証の入口、段のコマンド、実システムの確認のコマンドは、終了コードつきで hook が記録する。スクリプトの中から呼ぶと記録されないので、直接実行する。
- **統合の入口**: diff-review の記録(must と claim_only が 0)、閉じていない欠陥の記録が無いこと、`fix` 型のコミットがあるブランチではそのブランチの上で開いた欠陥の記録、検査を弱める変更が無いこと。hymme の台帳を持つリポジトリでは、変わったコードに対する検証のやり直し、実ログの突き合わせ、段の宣言(`tasks/stages.md`)、実システムでの確かめ、PR の本文の「影響の範囲」と「検証」の見出しも要る。
- **例外**: 検査を外すには `hymme exception request <検査> --until <日付> --reason <理由>` で申請し、ユーザーが承認する。ユーザーの確認そのものと、閉じていない欠陥の記録の検査は外せない。

止められたら、表示されたメッセージの手順に従う。検査をよける別の経路を探さない。
