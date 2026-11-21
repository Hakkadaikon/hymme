---
name: loopeng-modelcheck
disable-model-invocation: true
description: >
  loop-engineering の中ループ(設計検証)。TLC で TLA+ spec をモデル検査し、さらに spec 自体へ
  機械的ミューテーションを注入して「検査の強さ」を mutation oracle で検証し、最後に初期状態・不変条件・temporal 性質・遷移の文面を
  独立した読み手に平文へ戻させて要件と突き合わせる。
  「モデル検査して」「TLC を回して」「spec の mutation」「survivor を潰して」と言われたとき、
  または loop-engineering ルーターから中ループとして委譲されたときに使用する。
  前提: loopeng-formalize が生成した <Name>.tla / <Name>.cfg が tasks/loopeng/ にあること。
  無ければ先に loopeng-formalize へ戻る。通常は loop-engineering ルーターの判断を通ってから使う。
---

# loopeng-modelcheck (中ループ: 設計を検査し、検査の強さ自体を検証する)

`loop-middle SPEC=<Name>` を回す(駆動装置は [`../_shared/loopeng-toolchain.md`](../_shared/loopeng-toolchain.md))。
**前提**: `tasks/loopeng/<Name>.tla` / `<Name>.cfg` があること。無ければ **loopeng-formalize** へ戻る。確認の一覧(`tasks/loopeng/<Name>.claims.md`)をユーザーが承認していること。承認が無いか、承認のあとに一覧を変えていると `loop-middle` は hook に止められる。

0. **静的検査**: TLC の前に `loopeng/bin/tla_lint.sh` が SANY で構文・意味解析し、spec に `@type:` 注釈があれば Apalache で型検査する。`loop-middle` は自動で通し、`tlc` を直接叩く経路は hook(`hooks/loopeng-lint-gate.sh`)が止める。エラーが出たら spec を直してから先へ進む。
1. **model-check**: TLC が `Inv` を全到達状態で検査。`No error` なら設計は不変条件を守る。反例が出たら穴 → 内ループ(**loopeng-gherkin**)へ。
2. **mutation oracle**: spec に機械的ミューテーションを注入し、TLC が検出(killed)するか確認する。killed は性質違反(とタイムアウト)だけで、構文エラーの mutant は invalid、TLC の実行時エラーで止まった mutant は unverified として別に数える。unverified は意味の通る書き換えで再検査するまで証拠にしない。

**survivor が出たら spec が弱い。** 真の survivor が 0 になり、unverified を全件、意味の通る書き換えで再検査し終えるまで回す。oracle の出力メッセージや終了コードは完了の判定に使わない(equivalent や再検査済みの unverified が残っていても、oracle はそれを知らないため)。これが「検証器を検証する」上位ループ。

> survivor の大半は **equivalent-mutant**(kill 不能)。見分け方・判定手順・打ち切り基準は [`references/mutation-oracle.md`](references/mutation-oracle.md)。「真の安全性 survivor が 0」で打ち切ってよい。

`loop-middle` が回すのは上の2段まで。両方が緑になったら3段目に進む。3段目の入力ファイルと前件到達の証跡は式を書いた側(委譲していれば modeler)が作り、読み手の dispatch と判定はコントローラが行う。

3. **文面の往復確認**: 初期状態・不変条件・temporal 性質・遷移の文面(入力の範囲は共有手順の手順 1)を独立した読み手に平文へ戻させ、EARS と突き合わせる。検査が緑でも、式が要件と違うことを言っていれば何も保証しない。手順・担当・判定は [`../_shared/faithfulness-check.md`](../_shared/faithfulness-check.md)。
4. **ユーザーの2回目の確認(状態遷移図)**: 往復確認が終了条件を満たしたら、`hymme chart draw <Name>` を実行する。TLC を回し、到達する状態遷移図(Mermaid)と規則ごとの結果を `tasks/loopeng/<Name>.chart.md` に書く。破れた規則にはそこへ至る最短の経路が付く。破れた規則か検査されなかった規則が残れば exit 1 で、設計を直して描き直す。どちらも無くなったら `hymme chart request <Name>` を実行する。hook が図のファイルの中身と承認コードをユーザーに表示し、ユーザーが `承認 <承認コード>` とだけ入力すると承認が記録される。申請の前に、往復確認で `partial` が残った要件をユーザーに伝える(hook が表示するのは図のファイルだけ)。

**往復確認と状態遷移図は別のことを確かめる。** 往復確認では、式が要件と同じことを言っているかを独立した読み手とコントローラが確かめる。状態遷移図では、検査した結果の振る舞いが意図どおりかをユーザーが確かめる。往復確認で式を直すと spec が変わり、図は今の spec から作られていないとして作り直しになるので、先に往復確認を済ませる。図の承認のあとに spec か cfg を変えたときも、描き直して承認を取り直す。到達した状態が多いと図は省かれ、規則ごとの結果だけになる。モデルを小さくすると図が描ける。

状態遷移図の承認が無いと、`trace_check.py`(loopeng-tracecheck)と、実ログの突き合わせを求める統合の入口が止まる。申請するのはコントローラ。modeler はユーザーと対話できないので申請しない。

ユーザーが図を見て項目を直したいと言ったら、EARS、モデル、確認の一覧の順に作り直し、一覧の承認から取り直す(手順は [`../loopeng-formalize/SKILL.md`](../loopeng-formalize/SKILL.md) の「ユーザーの確認」)。

## 同じ規則で2回落ちたとき

修正を挟んでも同じ規則で2回続けて落ちると、次の検証の入口は hook に止められる(spec を変えずに回し直しただけなら数えない)。同じ前提に立った修正を重ねているおそれがあるので、次の修正の前に前提を確かめる。

`tasks/loopeng/<Name>.premise.md` に次の3行を書く。2回目の失敗より新しいことが条件。

```markdown
- 前提: <失敗した修正が共通して置いていた仮定を1文で>
- 観測: <その前提が偽なら結果が変わる観測を1つ>
- 結果: <観測した結果>
```

観測は次の修正より先に行う。失敗の大きさだけでなく、どの入力や経路で落ちたかの分布を見る。結果が前提と食い違ったら、前提が予測しなかった、失敗に共通する点を探す。この記録は SMT 経路と実ログの突き合わせでも同じ場所に書く。

動かないとき(TMPDIR/JDK 即死、TLC スクラッチ、トレース形式の罠)はまず [`references/troubleshooting.md`](references/troubleshooting.md)。

## やらないこと

- **真の survivor**(到達状態を変えるのに緑=設計の穴)を残したまま「設計検証済み」と言わない。一方 equivalent-mutant を 0 にしようと無限に粘らない([`references/mutation-oracle.md`](references/mutation-oracle.md))。
- 反例が出たのに spec だけ直して握りつぶさない。反例はまず **loopeng-gherkin** で受け入れ仕様に固定してから設計を直す。
- TLC スクラッチ等の生成物は `tasks/loopeng/` 配下・git 管理外([`../_shared/stealth-artifacts.md`](../_shared/stealth-artifacts.md))。

## 次の工程

- 反例が出た → **loopeng-gherkin** で Gherkin へ機械変換し、設計を直して外/中ループへ戻す。
- `No error` かつ真の survivor 0、unverified を再検査済み → modeler として委譲されていたなら、往復確認の入力ファイルと前件到達の証跡を作り、成果物のパスと状態を報告して終わる。読み手とレビュアーの dispatch はコントローラの仕事。
- 往復確認が共有手順の終了条件を満たし、状態遷移図をユーザーが承認した → 設計は固まった。loopeng-gherkin で正常系の受け入れシナリオを足す。
- 実装と実ログが手に入ったら → **loopeng-tracecheck** で実ログを spec に流し、実装が spec の許す遷移だけを辿っているかを確かめる。
