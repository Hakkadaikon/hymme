# formal-verification(Lean)/ test-design との橋渡し

設計が確定した後、**critical な実装片**(アルゴリズム・セキュリティ性質)は Lean で証明 → `formal-verification` skill。重い証明はコントローラが hymme:prover へ dispatch する(prover は検証ワーカー: `tasks/fv/` に成果物を残し、コミットせず、レビュアーを自分で呼ばない。SDD の implementer にはやらせない)。
TLA+ で「設計が正しい」、Lean で「実装が設計通り」を分担。どちらの成果も Gherkin / property test にする。両者を機械的に変換しようとしない(YAGNI)。

反例由来の Gherkin や証明済み述語を、機能レベルのテスト群(正常系・境界・異常系)へ展開する段では `test-design` skill 系を使う。設計の網羅は TLA+ が担うので、`test-design` は残りの機能テストの手法選定(同値分割・境界値・property-based 等)を担う。
その後の実装は superpowers:writing-plans の Task → superpowers:executing-plans(既定。SDD なら implementer)が superpowers:test-driven-development で実装する。Gherkin 由来のテストも実装する本人が書き、まず Red を見る。plan・テスト名に `S-xxx`/`R-xx`/`Inv` 名は書かない。

**実装検証時の追加ゲート2点**(完了前ゲートの一部。実地教訓: [`../../agentloop-extract/references/lessons.md`](../../agentloop-extract/references/lessons.md)):

- **検証環境が本番と同じ条件か**: 容量・タイムアウト等の環境依存パラメータをテストと本番で別の値にしない。可能なら本番の定数をテストと共有し、値を2箇所に書かない。検証と本番で値が違いうる定数は `tasks/surface.md` の「- 検証と本番で違う値:」に一覧で書く(無ければ「無し: 理由」)。この行が無いと統合の入口(PR の作成、既定のブランチへの merge など)で止まる。
- **緑判定で、パイプが exit code を隠していないか**: 検証ゲートは失敗しうるコマンドを単体で実行し、その exit code を直接確認する(`set -o pipefail` でも可)。

**証明済みでも実装が使っているとは限らない(結線チェック)**: Lean の証明は性質の正しさを保証するが、
**その証明対象の関数が実際の呼び出し経路から呼ばれているか**は証明系の対象外([`../../agentloop-extract/references/lessons.md`](../../agentloop-extract/references/lessons.md) の
証明と実装の非対称)。証明済み述語を実装へ渡したら、対応する関数が本番コードパスから呼ばれていることを
grep か呼び出しグラフで確認する。呼ばれていない証明はデッドコードで、緑のままでも効果が無い。

**実装後は実ログで spec と実装を突き合わせる**: 実装が動いたら、実システムの状態ログを spec と突き合わせて、spec の許さない遷移が無いかを確かめる(agentloop-tracecheck、`trace_check.py`)。テストとレビューは「書いた経路」しか見ないが、実ログは実装が実際に通った経路を見る。並行の実装はアトミック版と素朴版の spec を両方用意し、ログがどちらを満たすかで実装の実体を確定させる。検証が写したコードをこの変更で変えているなら、統合の入口は正常系・高負荷・障害注入のログが通り、わざと壊した実装のログが不一致になった記録を求める(ログの名前と採り方は agentloop-tracecheck)。

**検証が写したコードを変えたら、検証をやり直す**: 検証容易性の台帳の「## 対象」に挙げたファイルをこの変更で変えていると、統合の入口はその名前の検証をこの変更に対して実行し直して通った記録を求める。変更を4つに分ける手順は [`../../verifiability/SKILL.md`](../../verifiability/SKILL.md) の「対象のコードが変わったとき」。

**実装後は確定した不変条件で実装を突き合わせる**: 実装 Task が済んだら、diff-review を `conformance` レンズ付きで実行し、spec の要件・受け入れ条件(と `tasks/loopeng/` の不変条件)を性質一覧として渡す。テストが通る経路だけでなく、全経路で不変条件が守られるかを論証させる段で、テストを書き忘れた経路が見つかる。
