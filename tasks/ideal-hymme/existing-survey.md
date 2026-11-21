# 既存部品の調査(台帳 0-09 と 0-10)

調査日は 2026-11-21 です。対象は hymme 0.13.1 (923867f) です。読み取りだけを行い、ほかのファイルは変えていません。

この文書は `tasks/ideal-hymme.md` の行 0-09 と 0-10 の結果です。進捗は台帳で消し込みます。

パスはすべてリポジトリ直下からの相対です。行番号は 923867f の時点のものです。

## 1. 要約

- 台帳のフェーズ1〜5は85行あります。判定は「無い」38行、「一部在る」45行、「既に在る」2行です。
- 「既に在る」は 3-18 と 5-10 です。どちらも既存の規則と文面が重なります。
- 前提は正しいが、既存の規則と衝突する行が5つあります(1-06、4-03、4-15、5-10、5-11)。
- `loopeng/bin/` の道具は、どれも実行の記録をファイルに書きません。失敗の内容は標準出力と標準エラーにだけ出ます。
- `make loop-middle` と `make loop-inner` の終了コードは、道具の判定を表しません。Bash の終了コードを読む方法(0-05)では、この2つの結果を記録できません。
- 調査中に `hooks/pr_review_gate.py:63` の誤検出を1件踏みました。4.5 節に書きます。

## 2. A 台帳の「今は無い」の見直し

読んだ範囲は依頼の一覧の全ファイルです。判定のために、`skills/loop-engineering/`、`skills/loopeng-formalize/`、`skills/loopeng-tracecheck/`、`skills/verifiability/`、`skills/test-design/`、`skills/ledger-flow/`、`skills/using-hymme/`、`hooks/`、`README.md` も読みました。

### 2.1 件数

| フェーズ | 行数 | 無い | 一部在る | 既に在る |
|---|---|---|---|---|
| 1 | 21 | 12 | 9 | 0 |
| 2 | 16 | 7 | 9 | 0 |
| 3 | 19 | 10 | 8 | 1 |
| 4 | 17 | 6 | 11 | 0 |
| 5 | 12 | 3 | 8 | 1 |
| 計 | 85 | 38 | 45 | 2 |

### 2.2 フェーズ1

| 行 | 判定 | 既に在るもの | 台帳の行との違い |
|---|---|---|---|
| 1-03 | 一部在る | `hooks/gate_targets.py:149-257` が `cd`、`env -C`、`make -C`、`bash -c`、heredoc、`$(…)` を追います。`SPEC=` の無い呼び出しは `Spec` として扱います(`hooks/gate_targets.py:278-280`)。`tlc` の直接の実行は `hooks/loopeng-lint-gate.sh:44-59` が見つけます。 | 解析は3つに分かれています。`hooks/loopeng-extract-gate.sh:13` は先頭の語しか見ないので、`cd x && loop-middle` を通します。同じファイルの 23-25 行は `SPEC=` が無いと通します。`apalache-mc` と `lean` の直接の実行は、どの hook も見ていません。作業は新規の実装ではなく、`gate_targets.py` への統合です。 |
| 1-04 | 一部在る | 方針は hook ごとに在ります。解析できないときに止めるのは `hooks/verifiability-gate.sh:30-34` と `hooks/pr_review_gate.py:47-48` です。道具が無いときに止めるのは `hooks/verifiability-gate.sh:56` です。道具が無いときに通すのは `hooks/loopeng-lint-gate.sh:84-88` です。解析できないときに通すのは `hooks/loopeng-lint-gate.sh:35-36` と `hooks/loopeng-extract-gate.sh:9` です。 | 1つの表はありません。上のとおり hook どうしで逆を向いています。対話できない実行の扱いは、どこにもありません。 |
| 1-05 | 一部在る | `skills/diff-review/SKILL.md:102-107` の3行(commit、lenses、must)。`skills/ledger-flow/SKILL.md:28-29` の証跡ポインタ。`skills/test-catalog/SKILL.md:83` の転記元の sha256。 | 形はばらばらです。どれも本人が書きます。patch-id と道具のバージョンは、どこにもありません。 |
| 1-06 | 一部在る | `skills/_shared/stealth-artifacts.md:8-21` が置き場を決めています。作業ツリーの外に書く例は `hooks/git_guard.py:18-28` と `skills/rebase-flow/scripts/rebase-backup.sh:62-63` に在ります(`git rev-parse --git-path`)。 | 既存の規則は逆です。`stealth-artifacts.md:21` は「台帳は作業が起きる worktree の `tasks/` に置く」と決めています。`skills/_shared/loopeng-toolchain.md:19` も同じです。2.7 節に書きます。 |
| 1-08 | 一部在る | Makefile の `lint` が前提のターゲットです(`loopeng/Makefile.loopeng:40-61`)。hook が見ない経路でも静的検査が走ります。`loopeng/bin/tla_mutate_oracle.py:258-262` は変異の前に元の spec が通ることを確かめます。 | 記録(台帳、承認)を確かめる道具はありません。型は `lint` と同じにできます。 |
| 1-12 | 一部在る | 理由が必須の例外は `loopeng/bin/verifiability.py:133-143` に在ります。期限つきの通行は `hooks/git_guard.py:26` に在ります(30分)。除外に理由を求める規則は `skills/tdd-cycle/SKILL.md:216` に在ります。 | 理由、期限、承認の3つがそろった例外はありません。arm の印は本人がスクリプトを実行して書きます。 |
| 1-15 | 一部在る | 指標は入口のたびに測り直します(`hooks/verifiability-gate.sh:57`)。実装が入ったら対象を書き直す規則は `skills/verifiability/SKILL.md:22` に在ります。 | 測り直すのは指標だけです。レビュー合格の行は、対象が変わっても `[x]` のまま通ります(`hooks/verifiability-gate.sh:60`)。失効させるのはこの行です。 |
| 1-17 | 一部在る | ずれを「実装の穴」と「spec の書き漏れ」に分ける手順が `skills/loopeng-tracecheck/SKILL.md:32-34` に在ります。 | 2分類で、実ログの不一致だけが対象です。コードの変更から始まる4分類はありません。 |
| 1-20 | 一部在る | 読めない証跡で止める枝が `hooks/pr_review_gate.py:55-56` に在ります。 | 古い形式を見分ける処理はありません。新しい欄が無い証跡は、この枝に入ります。文言を直せば足ります。 |

1-10 は判定が「無い」ですが、行に挙げた直す箇所が足りません。3.1 節の一覧を使ってください。

### 2.3 フェーズ2

| 行 | 判定 | 既に在るもの | 台帳の行との違い |
|---|---|---|---|
| 2-01 | 一部在る | 式を平文に言い直して要件と突き合わせる表が `skills/_shared/faithfulness-check.md:15-26` に在ります。 | 作るのはモデル検査のあとです。読むのはコントローラで、作業者ではありません。「示さないこと」「破れたときの害」の欄はありません。 |
| 2-02 | 一部在る | モデルから捨てた領域を台帳に残す規則が `skills/loopeng-formalize/SKILL.md:42-54` に在ります。 | 残す先は抽出台帳の備考です。作業者に見せる手順はありません。有限にした値の範囲(`loopeng-formalize/SKILL.md:65` の `CONSTANT`)は、記録の対象になっていません。 |
| 2-04 | 一部在る | 「曖昧な点はモデル化前にユーザーへ確認」が `skills/loopeng-formalize/SKILL.md:15` に在ります。 | 確かめるのは曖昧な点だけです。一覧を作る手順はありません。 |
| 2-10 | 一部在る | witness に要件側の判断を付ける規則が `skills/loopeng-smt/SKILL.md:36` と 61 行に在ります。Lean は `skills/formal-verification/SKILL.md:41` に在ります。 | 検証の前の確認ではありません。食い違いが出たあとの確認です。 |
| 2-11 | 一部在る | modeler と prover は、検証容易性の検査で止まると BLOCKED で返します(`agents/modeler.md:23`、`agents/prover.md:21`)。確認待ちは NEEDS_CONTEXT です(`agents/modeler.md:25`)。 | 承認が無いときに返す決まりはありません。型は同じにできます。 |
| 2-12 | 一部在る | 状態グラフは `tlc -dump dot` で出しています(`skills/loopeng-modelcheck/references/mutation-oracle.md:78`)。`loopeng/bin/trace_check.py:260-261` は `-dump` を使っています。 | 用途は等価な変異の判定です。作業者に見せる図にはしていません。D-4 の候補に「TLC の dot 出力を使う」を加えられます。 |
| 2-13 | 一部在る | 材料は在ります。違反への経路は `loopeng/bin/trace_to_gherkin.py:61-85` が出します。往復確認の結果は `tasks/loopeng/<Name>.faithfulness.md` に在ります。 | 作業者に示す手順と承認はありません。 |
| 2-14 | 一部在る | 対応する式が無い要件は `missing` になります(`skills/_shared/faithfulness-check.md:26`)。空成立は TLC で確かめます(同 27-29 行)。形式手法の列が空の行は漏れとして扱います(`skills/loopeng-extract/SKILL.md:113`)。 | どれも本人かコントローラが表に書きます。機械の検査ではありません。図と spec のハッシュの照合はありません。 |
| 2-15 | 一部在る | 源泉を直して検査と往復確認をやり直す規則が `skills/_shared/faithfulness-check.md:30` に在ります。生成物を手で直さない規則は `skills/loopeng-gherkin/SKILL.md:28` に在ります。 | 承認の取り直しはありません。 |

### 2.4 フェーズ3

| 行 | 判定 | 既に在るもの | 台帳の行との違い |
|---|---|---|---|
| 3-01 | 一部在る | 段の定義は `skills/levels/SKILL.md:15-18` と `skills/levels-operational/SKILL.md:15-17` に在ります。単体で確かめられるロジックを結合や E2E だけで確かめていると指摘する観点が `skills/diff-review/references/test.md:36` に在ります。 | 6段の順の定義はありません。「要件とモデル」「実ログの突き合わせ」は段として扱っていません。 |
| 3-02 | 一部在る | 台帳が受け持つテストを glob で宣言する行が `skills/test-extract/assets/test-extract-template.md:8` に在ります。照合は `hooks/ledger_covers.py:9-11` です。 | 宣言するのは台帳の受け持ちです。段の区別はありません。同じ書式と照合の処理を使えます。 |
| 3-08 | 一部在る | 自分で踏んだ失敗も対象にする規則が `skills/review-feedback/SKILL.md:14` に在ります。記録先は `tasks/lessons.md` です(同 54 行)。 | 1行の教訓です。開く、閉じるという状態はありません。 |
| 3-09 | 一部在る | 教訓の1行は「指摘の種類・原因分類・埋め込み先」です(`skills/review-feedback/SKILL.md:54`)。モデルと実装の乖離は `tasks/fv/` に記録します(`skills/formal-verification/SKILL.md:91`)。 | 「見つかった段」「拾えたはずの最も前の段」「足したテストの名前」の欄はありません。 |
| 3-10 | 一部在る | 見逃した理由の4分類が `skills/review-feedback/SKILL.md:30-35` に在ります。抽出漏れの3つの原因が `skills/loopeng-extract/references/lessons.md:7-18` に在ります。 | 4分類はレビューが見逃した理由です。テストの段をすり抜けた理由ではありません。lessons.md の3つは、6分類の「要件の抜け」「モデルで捨てた領域」に当たります。 |
| 3-11 | 一部在る | バグを直す前に赤になる再現テストを書く規則が `skills/levels-operational/SKILL.md:169` と 175 行に在ります。橋渡しのテストを先に落とす規則は `skills/formal-verification/SKILL.md:89` に在ります。 | 本人が確かめます。スクリプトの実行と記録はありません。 |
| 3-13 | 一部在る | spec の書き漏れは要件に戻して formalize からやり直します(`skills/loopeng-tracecheck/SKILL.md:34`)。 | 対象は実ログの不一致だけです。承認の取り直しはありません。 |
| 3-17 | 一部在る | 水平展開の手順と、結果を報告に書く条件が `skills/review-feedback/SKILL.md:37-39` と 65 行に在ります。 | 台帳の行はこの手順を使うと書いています。足すのは欄の必須化だけです。 |
| 3-18 | 既に在る | 「以後バグが出たら、その欠陥を再現する最小テストを1本固定して回帰へ積む。台帳には新しい `T-ID` として追記する」(`skills/test-verify/SKILL.md:47`)。 | 規則は同じです。行は「3-09 の記録からこの規則へつなぐ」に直せば足ります。 |

### 2.5 フェーズ4

| 行 | 判定 | 既に在るもの | 台帳の行との違い |
|---|---|---|---|
| 4-01 | 一部在る | バグの入口は `skills/using-hymme/SKILL.md:24` です。修正案を「再現テスト、単一の変更、検証」で書く規則は `skills/gh-ci-investigate/SKILL.md:54` に在ります。実ログの手順は `skills/loopeng-tracecheck/SKILL.md:20-36` です。 | spec の有無で入口を分ける文面はありません。 |
| 4-02 | 一部在る | 3-11 と同じ箇所です。 | 「別の面で確かめた結果は合格にしない」に当たる規則はありません。 |
| 4-04 | 一部在る | 起動と主要な1経路を数秒で確かめる手順が `skills/levels-operational/SKILL.md:68-79` に在ります。外部の道具が使えるかを先に確かめる規則は `skills/_shared/parallel-delegation.md:103-109` に在ります。 | リポジトリごとの定義の形はありません。 |
| 4-10 | 一部在る | 「代表的な実ログ(正常系・高負荷・障害注入の各1本以上)が exit 0」が出口の条件です(`skills/loopeng-tracecheck/SKILL.md:40`)。reviewer は同じ引数で実行し直します(`skills/loop-engineering/reviewer.md:53`)。 | 条件は在ります。足すのは入口での機械の検査だけです。 |
| 4-11 | 一部在る | 違反のログを作ったら適合と判定された実例が `skills/loopeng-extract/references/lessons.md:53-62` に在ります。配線を緑と赤の両方で確かめる規則は `skills/loopeng-gherkin/references/gherkin-runners.md:29-31` に在ります。 | tracecheck の出口の条件には入っていません。 |
| 4-12 | 一部在る | 切り出しの前後で同じテストが通ることを台帳に貼る欄が在ります(`skills/verifiability/SKILL.md:44` と 51 行、`skills/verifiability/assets/verifiability-template.md:26-28`)。reviewer も見ます(`skills/verifiability/reviewer.md:30`)。通常のリファクタリングの規則は `skills/tdd-cycle/SKILL.md:17-19` と 58-63 行に在ります。 | 欄は在ります。本人が貼ります。足すのは機械の記録だけです。 |
| 4-13 | 一部在る | 実装を読みながら写す規則が `skills/loopeng-smt/SKILL.md:29` に在ります。性質を通常のテストに書き直して残す規則が同 68 行に在ります。 | 実関数とモデルの出力を突き合わせる手順はありません。 |
| 4-14 | 一部在る | 完了の前に新しい実行の証跡を求める規則が `skills/test-verify/SKILL.md:31` と `skills/using-hymme/SKILL.md:20` に在ります。 | 応答に貼る形です。記録と検査はありません。 |
| 4-15 | 一部在る | `smt_oracle.py` は性質の名前を行の頭に出します(`loopeng/bin/smt_oracle.py:111`)。`verifiability.py` は指標の名前を出します(`loopeng/bin/verifiability.py:263-266`)。 | TLC の系統は名前を捨てています。5 章に書きます。 |
| 4-16 | 一部在る | reviewer との往復は5回で人に返します(`skills/_shared/reviewer-loop.md:3`)。 | 道具の失敗の回数を数える処理はありません。 |
| 4-17 | 一部在る | 容量やタイムアウトをテストと本番で別の値にしない規則が、完了前の確認に在ります(`skills/loop-engineering/references/bridging.md:11`)。実例は `skills/loopeng-extract/references/lessons.md:27-39` です。 | 一覧にする欄はありません。 |

### 2.6 フェーズ5

| 行 | 判定 | 既に在るもの | 台帳の行との違い |
|---|---|---|---|
| 5-01 | 一部在る | conformance は Pass、Violation、Potential の3つに分けます(`skills/diff-review/references/conformance.md:24-28`)。Violation には破れる実例が要ります(同 40 行と 48 行)。確証の無い指摘には `[PLAUSIBLE]` を付けます(`agents/diff-reviewer.md:66-68`)。 | 5段階のうち「主張のみ」「机上でたどった」に近い区別は在ります。「実行した」「実物で再現した」はありません。3つの語と5段階の対応を決める必要があります。 |
| 5-02 | 一部在る | 実行できるレビュー担当は在ります。verification-reviewer の Bash には制限がありません(`agents/verification-reviewer.md:4`)。道具を自分で実行します(`skills/loop-engineering/reviewer.md:51-53`、`skills/verifiability/reviewer.md:18`)。 | diff-reviewer だけが許可リストに縛られています(`skills/diff-review/scripts/validate-readonly-bash.sh:36-37`)。設計の選択肢に「verification-reviewer と同じ形にする」があります。 |
| 5-05 | 一部在る | 追加したフィールドの構築箇所を grep で逆引きする観点が `skills/diff-review/references/design.md:39` に在ります。実装側の規則は `skills/tdd-cycle/SKILL.md:263` です。 | フィールドの追加に限った観点です。「安全だと言える根拠の事実を1つ書く」形ではありません。 |
| 5-06 | 一部在る | 6つのうち3つに近いものが在ります。「読み手の負荷」は `skills/diff-review/references/design.md:8-14` です。「先に削る」は同 35 行の YAGNI です。「型で不正な状態を防ぐ」は同 22 行です。 | 「境界で検証する」「領域をデータ構造に写す」「起きてはならない状態を隠すだけの修正」は design レンズにありません。近いものは別のレンズに在ります(`skills/diff-review/references/security.md:33`、`skills/diff-review/references/ops.md:10`)。 |
| 5-07 | 一部在る | 「並行なら?」の問いは test-extract に在ります(`skills/test-extract/SKILL.md:34`)。冪等性は concurrency レンズに在ります(`skills/diff-review/references/concurrency.md:34`)。 | loopeng-extract のひな形(`skills/loopeng-extract/assets/extract-template.md:24-49`)にはありません。並行と途中の失敗を拾うのは IaC の節だけです(`skills/loopeng-extract/SKILL.md:62`)。 |
| 5-09 | 一部在る | テストの一覧が `README.md:123` に在ります。hook が止める入口と条件は `skills/verifiability/SKILL.md:14-23` に在ります。 | 規則と強制の手段を並べた表はありません。 |
| 5-10 | 既に在る | 失敗を1回踏んだ時点で、観点を hook、テスト、Lint、レビューの基準のどれかに埋め込む手順が在ります(`skills/review-feedback/SKILL.md:14` と 41-50 行)。 | 既存の規則は1回目で埋め込みます。台帳の行は2回目です。2.7 節に書きます。 |
| 5-11 | 一部在る | テンプレートが無いときの構成に「動作確認」と「影響範囲・注意点」が在ります(`skills/pr-create/SKILL.md:97-110`)。レビューの証跡を動作確認に書く規則が同 112 行に在ります。 | 不要な節は省けます(同 95 行)。テンプレートが在るリポジトリでは節を足せません。2.7 節に書きます。 |
| 5-12 | 一部在る | 負荷テストの6つの手順と5つの確認が `skills/nonfunctional-perf/SKILL.md:46-61` に在ります。計測してから直す順は同 84-89 行です。根拠の無い最適化への指摘は `skills/diff-review/references/performance.md:13` です。 | pstack の7つの問いは手元にありません。重なりは 0-11 で照合してください。 |

### 2.7 前提は正しいが、既存の規則と衝突する行

- 1-06: `skills/_shared/stealth-artifacts.md:21` は、台帳を worktree ごとに置き、作成時にコピーし、終わったら捨てると決めています。`skills/ledger-flow/SKILL.md:53` も同じです。「別の worktree からも同じ記録が読める場所」は、この規則の変更になります。hook は cwd か git のトップを基準に `tasks/` を探します(`hooks/loopeng-extract-gate.sh:27`、`hooks/pr_review_gate.py:35-50`、`hooks/test-design-extract-gate.sh:34-45`)。
- 4-03: micro-commit は「関数とそのテストは1つのコミットにする」と決めています(`skills/micro-commit/SKILL.md:35`)。「各コミットのあとでコードが動く」も条件です(同 34 行)。失敗する再現を修正より前のコミットに置く形は、両方に反します。
- 4-15: 不変条件の名前を成果物に出すと、手法の痕跡を本体に漏らさない規則に触れます(`skills/_shared/stealth-artifacts.md:32-36`)。記録の置き場を git の管理外に限る必要があります。
- 5-10: 2.6 節のとおりです。2回目を待つ文面は、既存の「2回目を待つ理由は無い」(`skills/review-feedback/SKILL.md:14`)と逆です。
- 5-11: テンプレートの骨組みは変えられません(`skills/pr-create/SKILL.md:18` と 86-88 行)。`skills/pr-create/scripts/template-check.sh:99-117` は、足した見出しを EXTRA として止めます。

## 3. 台帳を直すべき行

| 行 | 直す内容 |
|---|---|
| 1-03 | 「解析を1つにまとめる」を「`hooks/gate_targets.py` に寄せる」に改めます。`loopeng-extract-gate.sh` と `loopeng-lint-gate.sh` の独自の解析を置き換える作業を明記します。 |
| 1-04 | 今の hook の方針が逆を向いていることを前提に加えます。 |
| 1-06 | `stealth-artifacts.md:21`、`loopeng-toolchain.md:19`、`ledger-flow/SKILL.md:53` の worktree の規則を直す対象に加えます。 |
| 1-07 | `loop-*` には記録を書く道具がありません。TLC を包むスクリプトを新しく作る作業を加えます(5.3 節)。hook と reviewer が道具を呼ぶ回も記録が書かれる点を、設計の論点に加えます(5.4 節)。 |
| 1-10 | 直す箇所を 4.1 節の一覧に差し替えます。`hooks/verifiability-gate.sh`、`skills/verifiability/SKILL.md`、`skills/verifiability/reviewer.md`、`skills/_shared/parallel-delegation.md` が抜けています。 |
| 1-14 | Web の画面で PR を作る経路(`skills/pr-create/references/platforms.md:60-67`)は hook から見えないことを加えます。語の一致だけで止める誤検出(4.5 節)を直す作業も加えます。 |
| 1-15 | 対象は「レビュー合格の行の失効」に絞ります。指標は既に毎回測り直しています。 |
| 2-01 | `faithfulness-check.md` の表との関係を決めます。同じ言い直しを2回作らないためです。 |
| 2-02 | 捨てた領域は抽出台帳の備考に既に在ります。一覧はそこから写す形にします。 |
| 2-12 | D-4 の候補に TLC の dot 出力を加えます。 |
| 3-10 | `review-feedback/SKILL.md:30-35` の4分類との関係を決めます。 |
| 3-18 | 新しい作業ではなく、`test-verify/SKILL.md:47` の規則へつなぐ行に改めます。 |
| 4-03 | `micro-commit/SKILL.md:34-35` との衝突を解く方針を加えます。 |
| 4-10 | 条件は既に在ります。「入口で機械に検査させる」だけに改めます。 |
| 4-12 | 欄は既に在ります。「本人が貼る欄を機械の記録に置き換える」に改めます。 |
| 4-15 | 対象の道具を明記します。名前を捨てているのは `tla_mutate_oracle.py`、`trace_to_gherkin.py`、Makefile の `check-spec` です。 |
| 5-01 | conformance の3つの語と5段階の対応を決める作業を加えます。 |
| 5-02 | 選択肢に「verification-reviewer と同じ形」を加えます。 |
| 5-10 | 既存の規則は1回目で埋め込みます。回数の条件を外すか、既存の文面を直すかを決めます。 |
| 5-11 | テンプレートが在るリポジトリでの扱いを加えます。 |

## 4. C 影響を受ける既存の箇所

### 4.1 レビュー合格の `[x]` を機械の記録に置き換える

- `hooks/verifiability-gate.sh:5`、`:17`、`:60`
- `skills/verifiability/SKILL.md:20`、`:23`、`:52`
- `skills/verifiability/assets/verifiability-template.md:34-36`
- `skills/verifiability/reviewer.md:14`、`:57`(台帳に引用する合格の1行)
- `skills/loop-engineering/reviewer.md:51`
- `skills/formal-verification/reviewer.md:26`
- `skills/_shared/parallel-delegation.md:93-98`
- `skills/_shared/reviewer-loop.md:9-11`
- `skills/loop-engineering/SKILL.md:40`
- `skills/formal-verification/SKILL.md:37`
- `README.md:37`
- `scripts/verifiability.test.sh:153-154`、`:292-294`、`:345-346`、`:480`
- `scripts/check-reviewer-checklist.sh:37-40`。reviewer.md の太字の見出しとチェックリストの項目名が一致しないと落ちます。項目を変えたら両方を直します。`scripts/check-reviewer-checklist.test.sh` も対象です。

合格の意味で本人が付ける `[x]` は、ほかにも在ります。置き換えの範囲に入れるかを決めてください。

- `skills/test-extract/assets/test-extract-template.md:13-15`、`:62-68`、`:85-94`(「緑確認済」)
- `skills/test-verify/SKILL.md:39`
- `skills/ledger-flow/SKILL.md:16-18`、`:28-29`、`:34`

### 4.2 `tasks/diff-review/evidence.md` の形を変える

- `skills/diff-review/SKILL.md:10`、`:17`、`:19`、`:88`、`:98-109`
- `skills/pr-create/SKILL.md:3`、`:19`、`:26`、`:55-64`、`:112`
- `hooks/pr-review-gate.sh:2-4`
- `hooks/pr_review_gate.py:12-20`、`:50-60`
- `skills/using-hymme/SKILL.md:22`
- `README.md:15`
- `agents/diff-reviewer.md:70-99`。must の件数をスクリプトが数えるなら、報告の形(`### must` の節)が入力になります。
- `skills/diff-review/scripts/validate-readonly-bash.sh:27-31`、`:36-39`。diff-reviewer はファイルに書けません。証跡を書くスクリプトは本体が実行する形になります。
- `skills/diff-review/scripts/collect-diff.sh:85-101`。base と head を出す箇所です。patch-id を足すならここです。`scripts/collect-diff.test.sh` も対象です。

この検査にはテストがありません(台帳 1-01 の前提どおりです)。

### 4.3 検査を PR 作成の1コマンド以外にも掛ける

- `hooks/pr_review_gate.py:63`
- `hooks/pr-review-gate.sh:2`
- `hooks/hooks.json:16-37`。対象は Bash だけです。MCP の道具は入っていません。
- `hooks/git_guard.py:103-110`、`hooks/git-guard.sh:6-7`。push を見ている箇所です。
- `skills/pr-create/SKILL.md:3`、`:14`、`:19`、`:22-30`、`:45`、`:64`、`:134-141`
- `skills/pr-create/references/platforms.md:22-33`、`:48-58`、`:60-67`
- `skills/using-hymme/SKILL.md:22-23`
- `skills/diff-review/SKILL.md:17`、`:109`
- `README.md:15`、`:20`

### 4.4 記録の置き場を変える

- `skills/_shared/stealth-artifacts.md:8-21`、`:45`
- `skills/_shared/loopeng-toolchain.md:19`
- `skills/ledger-flow/SKILL.md:41`、`:51`、`:53-54`
- `skills/_shared/faithfulness-check.md:11`、`:16`、`:29`
- `skills/verifiability/SKILL.md:19`、`:42`、`:60`
- `skills/verifiability/reviewer.md:5`
- `skills/review-feedback/SKILL.md:54`(`tasks/lessons.md`)
- `skills/formal-verification/SKILL.md:97`
- `skills/test-extract/SKILL.md:33`、`:63`
- `skills/test-extract/assets/test-extract-template.md:3-4`
- `agents/verification-reviewer.md:12`
- `agents/modeler.md:21`、`:23`
- `agents/prover.md:19`、`:21`
- `hooks/loopeng-extract-gate.sh:27`、`:44-45`
- `hooks/verifiability-gate.sh:42`、`:57`
- `hooks/gate_targets.py:69-71`、`:300-304`、`:315`
- `hooks/test-design-extract-gate.sh:34-35`、`:45`、`:91`
- `hooks/pr_review_gate.py:35-40`、`:50`
- `loopeng/bin/verifiability.py:232-234`。台帳の中のパスを cwd の配下に限っています。
- `scripts/verifiability.test.sh`(`tasks/` を含む行が40)、`scripts/test-design-extract-gate.test.sh`(同7)、`scripts/loopeng-trace-check.test.sh`(同1)

`tasks/loopeng`、`tasks/fv`、`tasks/test-design` を文面に含むファイルは、`skills/` に28、`agents/` に3あります。既存の台帳まで動かす場合だけ対象になります。

### 4.5 調査中に踏んだ誤検出

`hooks/pr_review_gate.py:63` は、コマンドの文字列に `gh` と `pr create` の語が在るだけで検査します。この調査で、その語を grep の検索語に入れた読み取りのコマンドが止められました。表示は「PR 作成前に diff-review スキルを must 指摘ゼロまで実施する」でした。

`hooks/gate_targets.py:40-43` は、入口を「実行される位置に在るか」で見分けています。同じ形にすれば直せます。

この1件は、フェーズ1の完了の条件にある「過去に実際に起きた失敗」の例に使えます。

## 5. B 道具の記録の調査

### 5.1 引数、終了コード、出力

| 道具 | 引数 | 終了コード | 標準出力の判定 |
|---|---|---|---|
| `tla_mutate_oracle.py` | `<spec.tla>`、`--cfg`、`--workers`、`--mut-timeout`、`--jobs`、`--since` | 0 survivor も unverified も無い。1 survivor あり。2 元の spec が通らない。3 unverified が残るか killed が0件。4 `--since` を読めない(`loopeng/bin/tla_mutate_oracle.py:16-20`) | 変異ごとに `killed`、`SURVIVOR`、`invalid`、`UNVERIFIED` とラベル。最後に `mutants: N  killed: N  survivors: N  unverified: N  invalid: N` |
| `smt_oracle.py` | `<model.py>`、`--timeout`、`--selfcheck` | 0 全判定が期待どおり。1 食い違いか、効いていない性質。2 モデルを読めない。3 Z3 が unknown(`loopeng/bin/smt_oracle.py:22-25`) | 性質ごとに `<名前>: HOLDS` か `VIOLATED` か `UNKNOWN`。続けて witness と `<- 期待は …` などの注記 |
| `trace_check.py` | `[--all] <Spec.tla> <run.jsonl>`、`--cfg`、`--timeout`、`--selfcheck` | 0 適合。1 不一致。2 入力の誤りか TLC のエラー(`loopeng/bin/trace_check.py:22`) | `適合: …` か `不一致: N 行目は …` と前後の状態。`--all` では最後に件数 |
| `verifiability.py` | `<台帳.md>`、`--selfcheck` | 0 全対象が合格か例外。1 指標が不合格。2 台帳の誤り(`loopeng/bin/verifiability.py:29-30`) | 対象ごとに `合格` か `不合格` と `[CCN n, NLOC n, 引数 n]`。続けて超えた指標の行 |
| `tla_lint.sh` | `<spec.tla>` | 0 通過。1 spec にエラー。2 使い方か道具の不在(`loopeng/bin/tla_lint.sh:11`) | `SANY 適合: …`、`Apalache typecheck 適合: …` か `省略`。エラーは標準エラー |
| `trace_to_gherkin.py` | ファイルか標準入力、`--selfcheck` | 0 変換した。反例が無いときも 0(`loopeng/bin/trace_to_gherkin.py:90-92`)。1 状態が0個 | Gherkin の本文 |
| `feature_to_c.py` | `--map`、`.feature` か標準入力、`--example`、`--selfcheck` | 0 生成した。1 シナリオが無い、対応表に無い語、`--map` が無い | C のコード |
| `gherkin_steps.py` | `--selfcheck` だけ | 0 | 使い方の文。pytest から読み込む部品で、判定の道具ではありません |

`tla_mutate_oracle.py` の 1 は意味が重なっています。spec が無いときと `tlc` が無いときも、`sys.exit(文言)` で 1 になります(`loopeng/bin/tla_mutate_oracle.py:128`、`:240`)。終了コードを記録に使うなら、この2つを 2 に分ける必要があります。

Makefile のターゲットは次のとおりです。

| ターゲット | 中身 | 終了コード |
|---|---|---|
| `loop-outer` | ひな形から `.tla` と `.feature` を作る(`loopeng/Makefile.loopeng:31-37`) | 判定はありません |
| `lint` | `tla_lint.sh`(同 44-45 行) | 道具のまま |
| `check-spec` | `lint` のあと TLC を直接実行(同 47-49 行) | TLC のまま |
| `mutate` | `lint` のあと oracle(同 54-58 行) | oracle の 3 を警告にして 0 で通す |
| `loop-middle` | `check-spec` と `mutate`(同 40 行) | 上の2つに従う |
| `loop-inner` | TLC の出力を `trace_to_gherkin.py` に流し、`tee` で `.feature` に書く(同 61-63 行) | 先頭の `-` とパイプで、TLC の失敗は伝わりません |

### 5.2 ファイルへの書き込みと記録

| 道具 | 書くもの | 実行や失敗の記録 |
|---|---|---|
| `tla_mutate_oracle.py` | 変異の `.tla` を spec の隣に作り、すぐ消す(`loopeng/bin/tla_mutate_oracle.py:212-225`)。TLC の作業用ディレクトリは一時の場所で、消す(同 131 行、148 行) | 無い |
| `smt_oracle.py` | 無い | 無い |
| `trace_check.py` | 一時ディレクトリに spec の写しと生成したモジュールを置き、消す(`loopeng/bin/trace_check.py:249-272`) | 無い |
| `verifiability.py` | 無い | 無い |
| `tla_lint.sh` | Apalache の出力先を一時に作り、消す(`loopeng/bin/tla_lint.sh:67-68`) | 無い |
| `trace_to_gherkin.py` | 無い。`.feature` に書くのは Makefile の `tee` | 無い |
| `feature_to_c.py`、`gherkin_steps.py` | 無い | 無い |
| Makefile | `loop-outer` が `.tla` と `.feature`。`loop-inner` が `.feature` を上書き。`check-spec` の TLC は cwd に `states/` などを残す | 無い |

台帳 0-09 への答えです。`loop-*`、`trace_check.py`、`smt_oracle.py` は失敗をファイルに残しません。

記録に近いものは、どれも本人が作ります。modeler は TLC と mutation の出力の場所を報告します(`agents/modeler.md:25`)。出力をファイルに落とすのは modeler 自身です。前件の到達の証跡は、本人が `<Name>.reach.log` に追記します(`skills/_shared/faithfulness-check.md:29`)。

`loop-inner` には副作用が1つ在ります。反例が無いとき、`trace_to_gherkin.py` は標準出力に何も出さず 0 で終わります。`tee` は空の内容で `.feature` を上書きします。`skills/loopeng-gherkin/SKILL.md:21` は、同じ `.feature` に正常系のシナリオを足すよう求めています。足したあとに `loop-inner` を回すと消えます。

### 5.3 失敗した規則の名前

| 道具 | 機械で読める形で出すか |
|---|---|
| `smt_oracle.py` | 半分です。行の頭が性質の名前です(`loopeng/bin/smt_oracle.py:111`)。落ちたかどうかは `<-` の注記の有無で見分けます。構造を持つ出力はありません。 |
| `verifiability.py` | 半分です。対象と指標の名前が文面に在ります。中では `(指標, 文言)` の組で持っています(`loopeng/bin/verifiability.py:260-268`)。出力するときに文に変えます。 |
| `tla_mutate_oracle.py` | 出しません。変異のラベル(`種類#番号@位置`)は読めます(同 166 行)。どの不変条件が変異を捕まえたかは捨てています。`run_mutant` は TLC の出力を返しません(同 223 行)。元の spec が落ちたときは、TLC の出力の末尾 2000 字をそのまま出します(同 261 行)。 |
| `trace_check.py` | 規則の名前はありません。不一致は行番号で出ます。`--all` は生成した不変条件の名前(`TC_InitOK`、`TC_StepOK`)を中で読みます(`loopeng/bin/trace_check.py:308-315`)。出力には初期状態か遷移かの違いとして出ます。 |
| `trace_to_gherkin.py` | 出しません。入力に在る `Invariant … is violated` の行を読み飛ばします(`loopeng/bin/trace_to_gherkin.py:39-58`)。シナリオの名前は固定です(同 61 行)。 |
| `tla_lint.sh` | 出しません。SANY と Apalache の出力を絞って標準エラーに流します(`loopeng/bin/tla_lint.sh:57`、`:72`)。 |
| Makefile の `check-spec` | 出しません。TLC の出力がそのまま流れます。 |

TLC の違反の行を読む正規表現は2か所に在ります(`loopeng/bin/tla_mutate_oracle.py:107`、`loopeng/bin/trace_check.py:308`)。名前を取り出す処理は、ここを共通にすると足せます。

### 5.4 記録と事前の確かめを足す位置

| 道具 | 記録を1件書く位置 | 動く前に確かめる位置 |
|---|---|---|
| `tla_mutate_oracle.py` | `main()` に `return` が7つ在ります(253、262、306、309、312、315、317 行)。判定の部分を、終了コードと集計を返す関数に分けます。321 行の `sys.exit(main())` の手前で1回書きます。 | `main()` の 246-253 行の直後です。ここは「遅い検査の前に早く落とす」ための箇所です。258 行の元の spec の実行より前に置きます。 |
| `smt_oracle.py` | `main()` の 162 行と 163 行のあいだです。`run()`(106-132 行)が性質ごとの結果も返すようにします。モデルを読めない枝(159-161 行)でも書きます。 | `main()` の 157 行の前です。158 行の `load()` は利用者のコードを実行します。その前に確かめます。 |
| `trace_check.py` | `main()` の 386 行のあとです。例外の枝(387-389 行)でも書きます。 | `check()` の 328-332 行です。spec とログを読む箇所で、ハッシュも取れます。台帳 4-09 のログの照合もここです。 |
| `verifiability.py` | `main()` の 306 行と 310 行のあいだです。対象コード無しの枝(303-305 行)と誤りの枝(307-309 行)でも書きます。 | `main()` の 302 行のあとです。この道具は検証の前提の側なので、確かめる記録は少なくなります。 |
| `tla_lint.sh` | `exit` が7か所在り、最後まで進んだときは `exit` を通らずに終わります。12 行のあとに `trap` を置き、終了コードを受けて書きます。68 行に別の `trap … EXIT` が在ります。上書きされるので、1つにまとめます。 | 31-34 行の spec の確認のあとです。 |
| `trace_to_gherkin.py` | `main()` の 93-98 行です。違反した不変条件の名前は `parse_states()`(39-58 行)で拾えます。 | `main()` の 89 行のあとです。 |
| Makefile | `check-spec`(48-49 行)には包む道具がありません。TLC を呼んで結果を書くスクリプトを新しく作り、ここから呼びます。`loop-inner`(63 行)も同じスクリプトを通します。 | `lint` と同じ形の前提のターゲットを作ります。31、40、54、61 行に足します。 |
| `feature_to_c.py`、`gherkin_steps.py` | 対象外でよいと考えます。判定をしません。 | 同じです。 |

設計の前に決めることが3つ在ります。

1. 道具は hook と reviewer からも呼ばれます。`hooks/verifiability-gate.sh:57` は入口のたびに `verifiability.py` を実行します。`hooks/loopeng-lint-gate.sh:76` は `tla_lint.sh` を実行します。reviewer は3つの道具を自分で実行します(`skills/loop-engineering/reviewer.md:51-53`)。「実行のたびに書く」だけでは、検査のための実行も記録になります。呼び手を分ける引数か、書かない指定が要ります。
2. 記録は道具の中で書く必要があります。Makefile は oracle の 3 を 0 に変えます(`loopeng/Makefile.loopeng:56-58`)。`loop-inner` は TLC の失敗を伝えません(同 63 行)。make や Bash の終了コードからは、判定を復元できません。
3. 記録の置き場は cwd に左右されます。Makefile は spec のディレクトリで実行します(同 7 行)。`verifiability.py` はリポジトリ直下で実行します(`skills/verifiability/SKILL.md:19`)。置き場を決めるときは、道具がリポジトリの根を自分で求める形にします。

## 6. 確かめていないこと

- pstack の文面は読んでいません。5-12 と 5-05 の重なりは、hymme の側だけを見た判定です。
- 道具は実行していません。終了コードと出力は、コードと docstring を読んだ結果です。4.5 節の誤検出だけは実際に起きました。
- 依頼の一覧に無いスキル(`strategy-*`、`levels-service`、`levels-system`、`process-static`、`oracle-*`、`flakiness-*`、`rebase-flow`、`reset-flow` など)は通読していません。3-01、4-04、5-07 には、これらに近い規則が在るかもしれません。
- 4.4 節の `skills/` と `agents/` の件数は、grep で数えた値です。
