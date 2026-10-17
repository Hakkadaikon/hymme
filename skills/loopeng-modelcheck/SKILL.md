---
name: loopeng-modelcheck
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
**前提**: `tasks/loopeng/<Name>.tla` / `<Name>.cfg` があること。無ければ **loopeng-formalize** へ戻る。

0. **静的検査**: TLC の前に `loopeng/bin/tla_lint.sh` が SANY で構文・意味解析し、spec に `@type:` 注釈があれば Apalache で型検査する。`loop-middle` は自動で通し、`tlc` を直接叩く経路は hook(`hooks/loopeng-lint-gate.sh`)が止める。エラーが出たら spec を直してから先へ進む。
1. **model-check**: TLC が `Inv` を全到達状態で検査。`No error` なら設計は不変条件を守る。反例が出たら穴 → 内ループ(**loopeng-gherkin**)へ。
2. **mutation oracle**: spec に機械的ミューテーションを注入し、TLC が検出(killed)するか確認する。killed は性質違反(とタイムアウト)だけで、構文エラーの mutant は invalid、TLC の実行時エラーで止まった mutant は unverified として別に数える。unverified は意味の通る書き換えで再検査するまで証拠にしない。

**survivor が出たら spec が弱い。** 真の survivor が 0 になり、unverified を全件、意味の通る書き換えで再検査し終えるまで回す。oracle の出力文言や終了コードは完了の判定に使わない(equivalent や再検査済みの unverified が残っていても、oracle はそれを知らないため)。これが「検証器を検証する」上位ループ。

> survivor の大半は **equivalent-mutant**(kill 不能)。見分け方・判定手順・打ち切り基準は [`references/mutation-oracle.md`](references/mutation-oracle.md)。「真の安全性 survivor が 0」で打ち切ってよい。

`loop-middle` が回すのは上の2段まで。両方が緑になったら3段目に進む。3段目の入力ファイルと前件到達の証跡は式を書いた側(委譲していれば modeler)が作り、読み手の dispatch と判定はコントローラが行う。

3. **文面の往復確認**: 初期状態・不変条件・temporal 性質・遷移の文面(入力の範囲は共有手順の手順 1)を独立した読み手に平文へ戻させ、EARS と突き合わせる。検査が緑でも、式が要件と違うことを言っていれば何も保証しない。手順・担当・判定は [`../_shared/faithfulness-check.md`](../_shared/faithfulness-check.md)。

動かないとき(TMPDIR/JDK 即死、TLC スクラッチ、トレース形式の罠)はまず [`references/troubleshooting.md`](references/troubleshooting.md)。

## やらないこと

- **真の survivor**(到達状態を変えるのに緑=設計の穴)を残したまま「設計検証済み」と言わない。一方 equivalent-mutant を 0 にしようと無限に粘らない([`references/mutation-oracle.md`](references/mutation-oracle.md))。
- 反例が出たのに spec だけ直して握りつぶさない。反例はまず **loopeng-gherkin** で受け入れ仕様に固定してから設計を直す。
- TLC スクラッチ等の生成物は `tasks/loopeng/` 配下・git 管理外([`../_shared/stealth-artifacts.md`](../_shared/stealth-artifacts.md))。

## 次の工程

- 反例が出た → **loopeng-gherkin** で Gherkin へ機械変換し、設計を直して外/中ループへ戻す。
- `No error` かつ真の survivor 0、unverified を再検査済み → modeler として委譲されていたなら、往復確認の入力ファイルと前件到達の証跡を作り、成果物のパスと状態を報告して終わる。読み手とレビュアーの dispatch はコントローラの仕事。
- 往復確認が共有手順の終了条件を満たした → 設計は固まった。loopeng-gherkin で正常系の受け入れシナリオを足す。
