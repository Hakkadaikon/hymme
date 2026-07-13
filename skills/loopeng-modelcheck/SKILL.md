---
name: loopeng-modelcheck
description: >
  loop-engineering の中ループ(設計検証)。TLC で TLA+ spec をモデル検査し、さらに spec 自体へ
  機械的ミューテーションを注入して「検査の強さ」を mutation oracle で検証する。
  「モデル検査して」「TLC を回して」「spec の mutation」「survivor を潰して」と言われたとき、
  または loop-engineering ルーターから中ループとして委譲されたときに使用する。
  前提: loopeng-formalize が生成した <Name>.tla / <Name>.cfg が tasks/loopeng/ にあること。
  無ければ先に loopeng-formalize へ戻る。通常は loop-engineering ルーターの判断を通ってから使う。
---

# loopeng-modelcheck (中ループ: 設計を検査し、検査の強さ自体を検証する)

`loop-middle SPEC=<Name>` を回す(駆動装置は [`../_shared/loopeng-toolchain.md`](../_shared/loopeng-toolchain.md))。2段。
**前提**: `tasks/loopeng/<Name>.tla` / `<Name>.cfg` があること。無ければ **loopeng-formalize** へ戻る。

1. **model-check**: TLC が `Inv` を全到達状態で検査。`No error` なら設計は不変条件を守る。反例が出たら穴 → 内ループ(**loopeng-gherkin**)へ。
2. **mutation oracle**: spec に機械的ミューテーションを注入し、TLC が検出(killed)するか確認する。

**survivor が出たら spec が弱い。** 「kills every mutant」相当になるまで回す。これが「検証器を検証する」上位ループ。

> survivor の大半は **equivalent-mutant**(kill 不能)。見分け方・判定手順・打ち切り基準は [`references/mutation-oracle.md`](references/mutation-oracle.md)。「真の安全性 survivor が 0」で打ち切ってよい。

動かないとき(TMPDIR/JDK 即死、TLC スクラッチ、トレース形式の罠)はまず [`references/troubleshooting.md`](references/troubleshooting.md)。

## やらないこと

- **真の survivor**(到達状態を変えるのに緑=設計の穴)を残したまま「設計検証済み」と言わない。一方 equivalent-mutant を 0 にしようと無限に粘らない([`references/mutation-oracle.md`](references/mutation-oracle.md))。
- 反例が出たのに spec だけ直して握りつぶさない。反例はまず **loopeng-gherkin** で受け入れ仕様に固定してから設計を直す。
- TLC スクラッチ等の生成物は `tasks/loopeng/` 配下・git 管理外([`../_shared/stealth-artifacts.md`](../_shared/stealth-artifacts.md))。

## 次の工程

- 反例が出た → **loopeng-gherkin** で Gherkin へ機械変換し、設計を直して外/中ループへ戻す。
- `No error` かつ真の survivor 0 → 設計は固まった。loopeng-gherkin で正常系の受け入れシナリオを足して実装へ渡す。
