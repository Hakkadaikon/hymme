---
name: test-verify
disable-model-invocation: true
description: >
  test-design の橋渡しと固定の工程。手法割り当て済みの T-ID 台帳を実装(superpowers:writing-plans の Task → SDD implementer の TDD、
  または hymme:coder)へ渡し、実行ゲート(網羅逆引き・緑・カバレッジ・flaky・mutation)で
  完了を検証し、緑にしたテストを回帰として CI に固定する。
  「テストの実装に渡して」「テストが全部書けたか確認して」「回帰に固定して」と言われたとき、
  または test-design ルーターから最終工程として委譲されたときに使用する。
  前提: test-catalog で全 T-ID に手法が割り当て済みであること。無ければ先に test-catalog
  (台帳自体が無ければ test-extract)へ戻る。通常は test-design ルーター経由で使う。
---

# test-verify (実装への橋渡し・実行ゲート・回帰固定)

割り当てが済んだ台帳のトレーサビリティマトリクス(振る舞い→手法→テスト名)を満たすよう実装側へ渡し、
自己申告でなく実行ログで完了を検証し、回帰として固定する。
**前提**: 全 T-ID に手法割り当て済み。未了なら **test-catalog** へ、台帳が無ければ **test-extract** へ戻る。

## 1. 実装/検証へ橋渡しする

- **実装の駆動**: superpowers のワークフロー下では、台帳の `T-ID` 行と `.feature` シナリオから superpowers:writing-plans の各 Task の「Write the failing test」を書き、そのテスト名を台帳の「テスト」列に転記する(`T-xxx` は plan に書かない)。実装は superpowers:subagent-driven-development の implementer(hymme:coder か superpowers 既定)が **REQUIRED SUB-SKILL:** superpowers:test-driven-development で1テストずつ消化する。plan の無い単発タスクなら T-ID リストをそのままテストリストとして hymme:coder に直接渡す。
- **設計に状態遷移、並行、順序があるとき**: テストで全 interleaving は踏めない。`loop-engineering`(TLA+)で設計をモデル検査し、反例を Gherkin の受け入れシナリオに落としてから、その述語をテストへ移す。
- **critical なアルゴリズムやセキュリティ性質**: 通常テストより強い保証が要るなら `formal-verification`(Lean 4)で証明し、証明済み述語を property-based test([`../generative-property/SKILL.md`](../generative-property/SKILL.md))の property として叩く。証明は implementer にやらせず、コントローラが hymme:prover を別 dispatch する。
- **`[~]` の行(設計の直し待ち)**: plan では1つの Task にまとめ、ほかの Task に混ぜない。ほかの行のテストとも、全状態を探索するような広いテストとも共有させない。共有すると、直し待ちの振る舞いまで期待値として固まる。行が `[x]` に戻るまで、その Task を完了にしない。
- **端から端まで通す Task を早めに置く**: Task をモジュールごとに分けるだけにしない。受け入れシナリオ1本を、フェイクの部品で端から端まで通す Task を早い順番に置く。部品どうしの噛み合わせの誤りを最後まで持ち越さない。
- 検証ワーカーの並列委譲(SDD 外のみ)は [`../_shared/parallel-delegation.md`](../_shared/parallel-delegation.md) の落とし穴に従う。

## 2. 実行ゲート(自己申告を信用しない)

**REQUIRED SUB-SKILL:** superpowers:verification-before-completion(主張の前に新鮮な実行証跡。agent の「緑」報告を信じず自分で走らせる)。以下は hymme の追加分で、基底の緑確認に**上乗せ**する。実行コマンドと生出力(終了コード、緑赤の集計行)を応答に貼る。貼れないなら未完。

1. **網羅(取りこぼし無し)**: 台帳の全 `T-ID` について、対応するテスト名が実在のテストファイル内に見つかることを grep で1行ずつ逆引きする。緑チェックはスイートの健全性を見るだけで、implementer が一部 `T-ID` を実装し忘れても「全緑」になる。存在チェックは緑チェックと別物として必ず回す。
2. **緑**: 全テスト緑・型検査クリーンは基底規範の対象。実行は修正範囲に絞る(`test-targeted` スキルの絞り込み運用)。
3. **カバレッジ**: 変更したコードの行(C0)と分岐(C1)のカバレッジが 100% であることを、計測コマンドの生出力で示す。未到達の扱いと除外の条件は [`../tdd-cycle/SKILL.md`](../tdd-cycle/SKILL.md) の「カバレッジ 100% をテストから先に満たす」に従う。
4. **flaky**: 性質ベースやメタモルフィック、並行を含むテストは seed を変えて複数回(最低でも数十回、または CI の連続成功)走っても落ちない。1回の緑では flaky は見えない。要因別の封じ込めは値の非決定性([`../flakiness-value/SKILL.md`](../flakiness-value/SKILL.md))と協調の非決定性([`../flakiness-concurrency/SKILL.md`](../flakiness-concurrency/SKILL.md))。
5. **強さ(critical のみ)**: 金額、セキュリティ、状態遷移など critical な `T-ID` は、緑に加えて mutation([`../mutation-testing/SKILL.md`](../mutation-testing/SKILL.md))を回し、survived がアサーション不足として残っていないことを確認する。全部に回すのは過剰(YAGNI)。

台帳の `T-ID` は、貼ったログ中の該当テスト名の緑に対応して初めて閉じる。

## 3. 緑にしたテストを回帰として固定する(守られ続ける状態へ渡す)

実行ゲートを通った緑は、その場限りでは守られ続けない。次の変更で黙って赤化しないよう継続実行に載せて初めて「テストが守られる」状態になる。

- 緑にしたテスト群を CI の継続実行対象に入れる([`../process-static/SKILL.md`](../process-static/SKILL.md) の CI 自動実行)。
- 変更したコードの行・分岐カバレッジ 100% を CI ゲートにし(差分カバレッジ)、割る変更をマージさせない。critical な `T-ID` は mutation もゲートにする。
- 以後バグが出たら、その欠陥を再現する最小テストを1本固定して回帰へ積む([`../levels-operational/SKILL.md`](../levels-operational/SKILL.md) の回帰テスト)。台帳には新しい `T-ID` として追記する。

## 完了前の必須ゲート(コンプライアンスレビュー)

完了扱いにする前(SDD なら最終 whole-branch レビューの前)に、コントローラが `hymme:verification-reviewer`(対象 `test-design`) サブエージェントを dispatch して外側から検査させる。
渡すもの: T-ID 台帳のパス、テストファイルと実行ログの場所。
レビュアーが挙げた違反(手法名のみで reference 未開封、T-ID とテストの存在不一致、実行ログ無しの「緑」報告、理由なしの優先度落とし)を解消してから完了とする。「緑と報告された」を証跡の代わりにしない。

## やらないこと

- **「緑」の報告だけで完了にしない。** 実行ログと型検査を自分で確認する。flaky は1回の緑では見えない。
- **API 境界の互換性維持を抜かさない。** 提供側と利用側を別々にテストするだけでは破壊的変更を見逃す。consumer-driven contract([`../nonfunctional-attributes/SKILL.md`](../nonfunctional-attributes/SKILL.md) のコントラクトテスト、粒度の選択は [`../levels/SKILL.md`](../levels/SKILL.md))で境界の互換を固定する。
- 完了条件は「対象範囲の全 T-ID が緑か、物理的に止まるまで」。自発的な区切りを完了と偽らない。
- テストのコメント・テスト名へ `T-xxx` 等の管理番号を書かない([`../_shared/stealth-artifacts.md`](../_shared/stealth-artifacts.md))。
