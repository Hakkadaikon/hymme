---
name: diff-review
description: コードレビューを頼まれたら必ず使う(組み込みの code-review より優先)。作業ブランチの差分を複数の観点でレビューする。「レビューして」「diff をレビュー」「〇〇観点で見て」と頼まれたとき、PR を作る前に使う。修正はしない。
user-invocable: true
argument-hint: "[レビュー範囲や観点(例: origin/main 以降 / security 観点も)。省略時は既定レンズで全差分]"
---

# diff-review: 多観点 diff レビュー

フローは 4 段階: **1. 差分収集(決定論)→ 2. レンズを決めて diff-reviewer agent を起動 → 3. 統合報告 → 4. 証跡出力**。
レビューは読み取り専用。修正・コミットはこのスキルの範囲外で、ユーザーの指示があってから別途行う。

## superpowers との関係

superpowers:subagent-driven-development のタスク単位レビュー(task-reviewer-prompt.md / re-review-prompt.md)と最終ブランチレビュー(requesting-code-review の code-reviewer.md)は superpowers のテンプレートで行い、本スキルはそれを置き換えない。本スキルを使う場面は 3 つ:

- **(a) PR 作成前**: pr-create が必須とし、`hooks/pr-review-gate.sh` が証跡(§4)を検査する。
- **(b) ユーザーの明示依頼**: 「レビューして」「〇〇観点で見て」。
- **(c) SDD 最終レビューの多観点補強**(任意): コントローラが code-reviewer.md の最終レビューに**加えて**本スキルを回す。順序は code-reviewer.md → 本スキル(同じ MERGE_BASE..HEAD)。本スキルの指摘は下の対応表で severity を読み替えて最終レビューの指摘リストに合流させ、fix 波(1 回)と scoped re-review は SDD の手順で回す(fix 波の後に本スキルを回して 2 回目の波を作らない)。本スキルの must が残るなら、code-reviewer.md の verdict に関わらず fix 波へ回し、merge 判断は scoped re-review の後にする。証跡ファイル(§4)はこの場面でも書き出す——後続の pr-create ゲートがそれを使う。executing-plans(inline)の最終レビューに足すときは、本スキルの must を Critical として1回の修正 pass に合流させ、executing-plans の規則どおり再レビューはしない。

diff-reviewer ワーカーはサブエージェントを起動しない。agent の分割はこのスキル(オーケストレータ)だけが決める。

### severity 対応表

| hymme(diff-reviewer) | superpowers(Critical / Important / Minor) |
|---|---|
| must | Critical |
| want+ | Important |
| want | Minor |
| nit | Minor |
| `[PLAUSIBLE]` | 読み替え後も併記。severity を上げも下げもしない |

## 1. 差分収集

`<skill-dir>` はこのファイルのあるディレクトリ。

```bash
bash <skill-dir>/scripts/collect-diff.sh manifest [<base-ref>]
```

- 出力: レビュー範囲(base / head の sha)・コミット一覧と統計・未コミット変更・未追跡ファイル・除外ファイル(lockfile 等は統計のみ)。総変更が小さければ全文 diff も同梱される
- `NO_CHANGES` が返ったら「レビュー対象の変更がない」と報告して終了する
- ユーザーがコミット範囲・ファイル等を指定した場合は base-ref 引数で範囲を合わせる

manifest はメインセッションで **1 回だけ**実行し、出力を次段で各 agent の prompt にそのまま注入する(agent 側に再収集させない)。メインセッションで精読・分析はしない。

## 2. レンズ決定と起動

### レンズ registry

- **既定**(無指定時に適用): `design`(設計・可読性)/ `test`(テスト設計・網羅性)
- **オプション**(指定時のみ適用): `security`(セキュリティ / OWASP Top 10)/ `docs`(ドキュメント整合)/ `performance`(計算量・N+1・データサイズ)/ `compat`(互換性・移行安全)/ `ops`(可観測性・運用)/ `concurrency`(並行性)/ `spec`(仕様一致)/ `conformance`(不変条件・性質を実装が全経路で守るかの証明試行)/ `fresh-eyes`(初見)
- キーワード対応: 「設計」「可読性」→ `design`、「テスト」→ `test`、「セキュリティ」「security」→ `security`、「ドキュメント」「docs」→ `docs`、「パフォーマンス」「性能」→ `performance`、「互換」「マイグレーション」「移行」→ `compat`、「運用」「ログ」「可観測性」→ `ops`、「並行」「排他」「race」→ `concurrency`、「仕様」「要件」「依頼どおり」→ `spec`、「適合」「不変条件」「性質を守っているか」「conformance」→ `conformance`、「初見」「fresh eyes」→ `fresh-eyes`

適用ルール:

- **追加指定**(例: 「〇〇観点も見て」): 既定レンズに**加えて**指定レンズを適用する
- **絞り込み指定**(例: 「〇〇だけ」「〇〇のみで」): 指定レンズだけを適用する
- `conformance` を適用するときは、性質一覧の場所(依頼文・spec・`tasks/loopeng/`・`tasks/fv/` のどれか)を agent prompt の「ユーザーの依頼」に含める
- registry に無い観点を指定されたら、その観点名をレンズの1つとして加え(agent を分けたときはいずれかのまとまりに入れ)、一般知識でレビューさせる

### 起動

適用レンズをまとめて diff-reviewer agent 1 体に渡す。全レンズが同じ差分を読むので、レンズごとに agent を分けると同じ差分と周辺コードを本数分読み直すことになる。分けるのは2つの場合だけで、分けた agent は **1 メッセージ内で同時に起動**する。`conformance` のように性質ごとの論証で長くなるレンズは、そのレンズだけを別の 1 体に分ける。レンズが4つを超えるときは、4つずつのまとまりに分けて1体ずつ渡す。agent の prompt には必ず以下を含める:

```
レンズ: <lens>[, <lens>...]
基準ファイル: ${CLAUDE_PLUGIN_ROOT}/skills/diff-review/references/<lens>.md(レンズごとに、レビュー開始前に Read すること)
ユーザーの依頼: <元の依頼の要約(範囲・重点の指定があれば含める)>

以下は収集済みの差分 manifest。manifest の再実行はしない。全文 diff が必要な単位のみ
${CLAUDE_PLUGIN_ROOT}/skills/diff-review/scripts/collect-diff.sh の commit / worktree / cumulative で取得する
(agent は独立コンテキストのため、ここだけは相対パスでなく絶対パス変数のまま渡す):

<manifest の出力をそのまま貼る>
```

manifest を全 agent に同一内容で渡すことで、レビュー範囲のスナップショットを固定する。

## 3. 統合報告

報告を 1 つに統合し、diff-reviewer の報告形式(must / want+ / want / nit の severity 順)で出力する:

- 冒頭に「対象: <範囲> / レンズ: <適用レンズ>」を明記する
- 同一 `ファイルパス:行番号` に複数レンズの指摘が重なったら 1 件に統合する。severity は最も重いものを採用し、レンズタグを併記する(例: `[design][security]`)
- `[PLAUSIBLE]` マークは統合後も維持する
- レンズ固有の付記(`conformance` の使った性質一覧・Pass 件数・フィルタ除外の一覧)は、統合報告の末尾にレンズ名を付けてそのまま残す
- 場面 (c) では、hymme 形式の統合報告に加えて、対応表で読み替えた Critical / Important / Minor の一覧を最終レビューへの合流用に出す(証跡 §4 の `must:` は hymme 形式の件数のまま)

### 完了条件

以下をすべて満たしたときのみレビュー完了とする。1 つでも欠けたら未完了:

- 起動した全 agent の報告を受領している(未完了の agent を残したまま統合しない)
- 全指摘が severity 順で 1 つの報告に統合されている(上記の重複統合を含む)
- 全レンズで指摘ゼロの場合は「指摘なし」と明言している。褒め言葉・社交辞令は書かない

## 4. 証跡出力

統合報告の後、レビュー証跡を以下の形式で書き出す:

```
tasks/diff-review/evidence.md (git 管理外、毎回上書き)
commit: <レビュー時 HEAD の full SHA>
lenses: <実施レンズをカンマ区切り>
must: <このレビュー実行で検出した must 指摘の件数>
```

PR 作成前ゲート hook がこのファイルを検査する(存在 && commit==現 HEAD && must==0 で通過)。
