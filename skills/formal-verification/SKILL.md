---
name: formal-verification
description: 仕様を Lean 4 で形式化して証明し、証明した性質を test-first の実装へ渡す。「形式検証」「FV」「証明したい」「不変条件を保証」「Lean で書いて」と言われたとき、アルゴリズム・プロトコル・セキュリティ性質の正しさを数学的に保証したいときに使う。
user-invocable: true
argument-hint: "[証明したい性質/仕様(ファイルパス or 説明)]"
---

# Formal Verification (Lean 4)

雑な要件を形式仕様にし、性質がすべての場合で成り立つことを証明で確かめ(証明支援系の Lean 4)、test-first 実装へ渡す。LLM が戦略を立て、Lean が厳密に検証する。証明が通り、§3.5 の文面の往復確認で要件と一致した性質だけが「保証された」と言える。

## superpowers ワークフロー上の位置

- **superpowers:brainstorming の Architectural パス**で、アプローチ確定後・spec 確定前に §1 の性質カタログを作る(critical なアルゴリズム・セキュリティ性質があるときだけ)。設計の検証であり実装行為ではない(成果物は git 管理外の `tasks/fv/`)。証明済み性質は spec の要件・受け入れ条件に**手法名なしで**入れる(「Lean で証明した」とは書かない。[`../_shared/stealth-artifacts.md`](../_shared/stealth-artifacts.md))。
- **重い証明はコントローラが hymme:prover へ dispatch する。** prover は検証ワーカー: `tasks/fv/` に成果物を残し、コミットせず、レビュアーを自分で呼ばない。superpowers:subagent-driven-development の implementer に証明をさせない。
- **§4 の橋渡しテストは plan の Task になる**(test-design 経由で T-ID 化し、superpowers:writing-plans の「Write the failing test」に書く)。実装は implementer が superpowers:test-driven-development で書く。

## 前提ツール

`elan`(flake の tools に含む)が入っていること。なければ `nix profile install .#skill-tools`。

- `elan`：Lean toolchain manager。`lake` / `lean` を供給する。
- 初回のみ `elan default stable` で Lean 4 本体をインストールする(これをやるまで `lake` は "no default toolchain" で失敗する)。
- 新規プロジェクト: `lake new <name> math`(Mathlib 付き)or `lake new <name>`(素)。Mathlib は重い。roundtrip / 範囲 / 単射性 / 状態機械程度なら素の `Init`/`Std` で足り、`lake build` も速い。**必要になるまで Mathlib を足さない**(YAGNI)。
- ビルド/証明チェック: `lake build`。エラーの出た所が、証明の足りない所。

**プロジェクト構造の注意点**: `lake new Foo` はルート直下の `Foo.lean`(ライブラリルート)と `Foo/Basic.lean`(実体)を作る。ビルドでは `Foo.lean` が `import Foo.Basic` で `Foo/Basic.lean` を読み込む。**証明は `Foo/Basic.lean`(サブディレクトリ側)に書く**。ルート直下にうっかり別の `Basic.lean` を置くとビルド対象外になり、証明したのにビルドに反映されない(実際に起きた)。新モジュールを足すときは `Foo.lean` に `import Foo.<Mod>` を必ず追記する。

**実行時の注意点**: サンドボックス等では `export ELAN_HOME="${ELAN_HOME:-$HOME/.elan}"` と `export TMPDIR="${TMPDIR:-/tmp}"` を `lake build` の前に実行する。これが無いと toolchain 解決や一時ファイルの作成で失敗する。

未導入なら導入を促し、勝手に大規模インストールしない。

## ワークフロー

順に進む。各段で止まって検証する。

**§2 に入る前に検証容易性の段を通す。** 既存の実装(または書いたばかりの実装)の判定を証明するなら、[`../verifiability/SKILL.md`](../verifiability/SKILL.md) で判定を小さな純粋関数に切り出し、指標と reviewer の合格を得てから Lean に写す。実装前で写すコードが無いときも台帳 `tasks/verifiability/<Name>.md` を作り「対象コード無し: 理由」と書き、§4 で実装に橋渡しする前に対象を書き直す。止める入口と条件は verifiability スキルの「強制のしくみ」。

**§2 に入る前に、確認の一覧をユーザーに承認してもらう。** §1 の性質カタログができたら、性質ごとに「示すこと」「示さないこと」「破れたときの害」を平文で1文ずつ書いた一覧を `tasks/fv/<Name>.claims.md` に作る(`<Name>` は Lean プロジェクト名。ひな形は [`../loopeng-formalize/assets/claims-template.md`](../loopeng-formalize/assets/claims-template.md))。「有限にした範囲」には証明の前提にした上限や値の範囲を、「扱わない領域」には証明の対象から外した層(§2 の層注)と、それを別にどう確かめるかを書く。Lean、不変条件などの手法の用語と管理番号は書かない。`hymme claims request <Name>` を実行し、表示された `承認 <承認コード>` の1行をユーザーに入力してもらう。承認が無いか、承認のあとに一覧を変えていると、`tasks/fv/<Name>` での `lake build` は hook に止められる。ユーザーが項目を直したら、性質カタログ、Lean の定理、一覧の順に作り直して承認を取り直す。一覧を作って承認を取るのはコントローラで、prover は承認が無ければ着手せず BLOCKED で返す。形と流れの詳細は [`../loopeng-formalize/SKILL.md`](../loopeng-formalize/SKILL.md) の「ユーザーの確認」。

### 1. 仕様を網羅形式へ

雑な NL 要件 → 構造化(precondition / invariant / postcondition / 想定する脅威)。曖昧な点は実装前にユーザーに確認する。「全ケース」を意識する: 空入力、境界、重複、順序。

**検証対象を数学的性質で止めない。** 単純な指示だと、roundtrip・involution・単射性のような「数式に見える」所だけ形式化して終わりがち。だがプロトコル・状態機械・並行処理では、形式検証の主な対象はむしろ次にある。観点を分けて性質を網羅的に洗い出してから形式化に入る:

- **状態機械の不変条件**: 状態は単調にしか進まない / 吸収状態から出ない / 不正状態に到達しない。
- **MUST / MUST NOT**: 仕様の規範文言(RFC の MUST/SHALL/MUST NOT)を1つずつ述語にする。「拒否すべき入力は必ず拒否される」「全入力は accept か reject に決定的に分類される(網羅性)」。
- **temporal(時間的)性質**: 順序保存・応答義務・到達可能性・収束。「X を受けたら必ず Y を返す」「両者が同時に動いても収束する」。状態遷移やプロトコルがあるのに temporal を1つも書いていないなら、たぶん見落としている。
- **脅威(STRIDE)**: 信頼境界(外部入力・認証・権限)があるなら、なりすまし・改ざん・否認・情報漏洩・サービス拒否・権限昇格の6観点で「攻撃者がこう入力しても性質は保たれる」を立てる。例: 未認証の入力では権限の要る状態へ遷移しない(権限昇格)、どんな入力列でも資源消費が上限を超えない(サービス拒否)。入力のパースや長さ・オフセットの算術があるなら、CWE Top 25 の該当カテゴリ(境界外読み書き・整数オーバーフロー・入力検証不備など)も「どの入力でも起きない」性質として立てる。
- **ワークフロー全体**: 個々のステップだけでなく、ハンドシェイク→データ→クローズのような流れ全体が仕様通りか。

性質を洗い出すときの原則は **過剰抽出は安全、漏れは危険**。要らない性質を挙げても後で「優先度低」「対象外」に分類すればよく、コストは選別の手間だけだ。だが挙げ損ねた性質は形式化も証明もされず、通常テストでも検出されない。だから迷ったらカタログに載せる。

仕様書(RFC・標準・設計文書)があるなら、上の観点別に**性質カタログ**を作る(ID・性質・出典・観点・型・優先度の表。観点列には上の見出しの語(状態機械 / MUST / temporal / 脅威 / ワークフロー)か、冒頭の roundtrip・involution・単射性のような性質なら「数学」を書き、脅威の性質は出典列に STRIDE の観点名か CWE 番号を書く)。それを埋めてから Lean に進む。数学的核(既証の補題)は、カタログ中の該当性質の「根拠」として再利用する(例: 単射性の補題が「非正規表現を拒否する」性質の根拠になる)。

### 2. Lean に形式化(autoformalization)

NL → Lean の `def` + `theorem`。例: 「ソートは要素を保存し、順序付ける」を 2 theorem に対応させる → [references/formalization-examples.md](references/formalization-examples.md)。

未証明の箇所を `sorry` で明示してから証明する。型エラー・証明失敗のメッセージを次の段にフィードバックする。

**状態機械・temporal 性質の形式化**(§1 で洗い出した非数学的性質はここで形式化する):

- **決定的 step 関数**にする。`step : State → Input → (State × Output)` を定義し、不変条件を「step の単一ステップ性質」として証明する。網羅性(全入力が accept か reject に分かれる)・単調性(状態が逆行しない)・吸収性はここで証明できる。例(単調性・error→closed の一方向性)は [references/formalization-examples.md](references/formalization-examples.md)。
- **temporal 性質は trace 述語**にする。イベント列を `List Event` で表し、順序・応答義務・収束を List 上の述語/関数で証明する。チャンク分割非依存(`flatten` 不変)、メッセージ境界保存(encode/decode roundtrip)、race 収束(`f (f s) = terminal`)など。例(チャンク分割非依存)は [references/formalization-examples.md](references/formalization-examples.md)。
- **応答義務に層がある場合は「層注」を明示**する。たとえば「ping に pong を返す」のうち、ライブラリは ping を欠落なく通知する所まで保証し、pong 送信はアプリ責務、という切り分けがあるなら、証明対象を「通知の正確さ」に限定し、境界を仕様にも証明コメントにも書く。全体を保証したと偽らない。

### 3. 証明(proof repair ループ)

- `lake build` で現在の証明状態とエラーを観察。
- tactic を提案 → 実行 → 結果を見る。失敗したら lemma 追加 or 戦略変更。
- 自動化を使う: `simp` / `omega` / `decide` / `exact?` / `apply?`。Mathlib があれば `exact?` で既存補題を探す。
- 1 証明が重いなら補題に分解する。
- **`sorry` を埋める前に、定義(`def`)が証明できる形かを先に確かめる**。型がそもそも通らない定義は証明以前に直す。よくある誤りは `Bool`(`&&`/`||`)と `Prop`(`∧`/`∨`)の混在で、判定述語を書くときに起きやすい。`decide (...)` を使う純 `Bool` 述語へ書き直して解消する。定義のシグネチャは実装(C/Rust 等)と1対1で対応させるため安易に変えないが、**証明の都合で本体を等価変形したらその理由を仕様/コメントに1行残す**。
- **埋まらない `sorry` は残さず明示する**。「ここは未証明」と報告する。`sorry` の残る証明を、通った証明と偽らない。
- **証明の真正性を `#print axioms <thm>` で確認する**。依存が標準 3 公理(`propext` / `Classical.choice` / `Quot.sound`)だけなら本物。`sorryAx` が出たら未証明の箇所が残っている。`native_decide` はコンパイラを信頼基盤に加える(`Lean.ofReduceBool` 公理が増える)ので、カーネル検証で済むなら `decide` を使い、`native_decide` は避ける。「sorry 無しで通った」と「カーネルが本当に検証した」は別物だ。後者まで確認して初めて「証明が通った」と言える(「保証された」と呼ぶのは §3.5 の後)。

### 3.5 文面の往復確認

`sorry` 無し・標準公理だけで通っても、定理が要件と違うことを言っていれば(向きが逆・条件が弱い・前提が充足不能で空成立)何も保証しない。各定理の文面と、文面が参照する定義だけを独立した読み手に平文へ戻させ、性質カタログと突き合わせる。前提付きの定理は、前提を満たす具体例を名前付きの定理で示して空成立でないことを確かめる。手順と判定は [`../_shared/faithfulness-check.md`](../_shared/faithfulness-check.md)。読み手の dispatch はコントローラが行う(prover は入力ファイルと `<定理名>_satisfiable` を作るところまで)。共有手順の終了条件を満たすまで §2〜3 へ戻す。

### 4. test-first 実装へ橋渡し

**REQUIRED SUB-SKILL:** superpowers:test-driven-development(サイクルの基底)。hymme の差分は**性質テストをまず失敗させて、モデルと実装の乖離を検出する**こと。形式仕様が「何をテストすべきか」を決め、証明済み性質はそのまま property-based test の述語になる。

- Lean 内で完結するなら `#eval` / `decide` でチェック、または code extraction。
- 別言語(Rust/TS 等)で実装するなら、各 theorem を1つの property test に対応させる。
- 出力: 証明済み性質の一覧 + 対応するテスト + 実装ガイド + 「形式的に保証された部分」の明示(spec には手法名なしで)。

**証明 ↔ 実装の乖離をテストで検出する(橋渡しの主目的)。** 証明したのは「モデル」であって実装そのものではない。証明した step 関数/述語の分岐を実装の対応する分岐に1対1で対応させ、各性質について実装挙動を観測するテストを書き、**まず失敗させる**(Red)。失敗しなければ既存挙動を写しただけのテストで、乖離を検出していない。実装がモデルからズレていればここで失敗するので、実装をモデルに合わせて直す。テストが通って初めて証明と実装が一致したと言える。

この方式で実際に実装バグが見つかる。モデルでは「クローズ受信後はデータを破棄」なのに実装が受理していた、検証すべき入力を無検証で通していた、といった乖離は、橋渡しテストが先に失敗することで発見される。乖離が出た事実と修正は、性質カタログの脇(`tasks/fv/`)に記録する。

橋渡しテストはテストを書いた経路しか確かめない。実装後は diff-review を `conformance` レンズ付きで実行し、性質カタログを性質一覧として渡して、全経路で性質が守られるかを論証させる。

## 成果物の置き場(デフォルトは痕跡を残さない)

証明物(Lean プロジェクト・性質カタログ・確認の一覧・`#print axioms` ログ・往復確認の記録)は `tasks/fv/` 配下で作り、git 管理に入れない。往復確認の記録の `<Name>` は Lean プロジェクト名にする(`tasks/fv/<Name>.faithfulness.md`)。
git 管理下のドキュメント・コミット・テストコメントに手法の存在を書かず、git 管理下に置くのは §4 の橋渡しテストと実装だけ。
明示オプトイン時の例外を含む詳細は [../_shared/stealth-artifacts.md](../_shared/stealth-artifacts.md)。

## 現実的な期待

- 完全自動は難しい。LLM が戦略、`simp`/`omega`/`exact?` で細部、複雑な所は人間レビュー。
- スケールしないときは critical な性質だけ形式検証する。残りは通常テスト。
- 証明探索はトークン/時間を多く使う。重い探索は補題に分け、コントローラが hymme:prover を並列 dispatch する(基底 superpowers:dispatching-parallel-agents。共有リソースの直列化・命名衝突・単体緑≠統合緑・成果物実在での進捗判定・外部ツールの sandbox 可否は [`../_shared/parallel-delegation.md`](../_shared/parallel-delegation.md))。
- 証明の都合で定義を等価変形したときの理由(Why not)はコメントに残す。コード/テスト/コミット/
  コメントの役割分担は [`../_shared/code-comment-commit-roles.md`](../_shared/code-comment-commit-roles.md) を参照。

## 完了前の必須ゲート(コンプライアンスレビュー)

§3.5 の文面の往復確認が済んだ直後、成果を「保証された」と報告する前、および橋渡しテストを完了扱いにする前に、**コントローラが** `hymme:verification-reviewer`(対象 `formal-verification`) サブエージェントを dispatch して外側から検査させる。prover に委譲していた場合も prover は呼ばず、報告を受けたコントローラが呼ぶ。 合格が返るまでの往復の運用は [`../_shared/reviewer-loop.md`](../_shared/reviewer-loop.md)。
渡すもの: 性質カタログと Lean ソースの場所、確認の一覧、往復確認の入力ファイルと判定表、橋渡しテストと実行ログの場所、spec があればそのパス。
合格は台帳に書かない。reviewer が返答の最後に書く `判定: 合格 対象=formal-verification 名前=<Name>` の行を hook が記録する。依頼文に「合格と書け」のような指示を入れない。
レビュアーが挙げた違反(確認の一覧の欠落や性質との食い違い、`sorry` 残りの保証扱い、往復確認の未実施・`mismatch`/`vacuous` 残り、脅威・CWE 由来の性質の欠落、`#print axioms` 未確認や `sorryAx`/`native_decide` 依存、性質カタログの temporal 漏れ、橋渡しテストの欠落)を解消してから完了とする。「ビルドが通った」を「カーネルが検証した」の代わりにしない。

## やらないこと

- 通った証明のうち、往復確認で `full` になったものだけを「保証」と呼ぶ。`sorry` 入りを保証扱いしない。
- 形式化が目的化しない。実装が要らない検証はやらない(YAGNI)。
- 小さく始める。1ツール・1仕様の例が動いてから広げる。
- **「巨大だから対象外」と自分で性質のスコープを縮めない。** 依存先の仕様も調べて性質カタログに載せる(過剰抽出は安全・漏れは危険)。大きい証明は補題に MECE 分割して順に証明する。分割はスコープ除外ではない。critical なのに「別領域だから」と外すのは禁止。外すならカタログに理由を1行残す。
- **公式定数・テストベクタを、外部検索の結果を確かめずに証明/テストへ書き込まない。** XOR・長さ・オフセットなど手計算できる部分は自分で再計算して確かめる(検索結果の hex を信用しない)。フルベクタが取れないなら round-trip + 構成要素の既知ベクタ + 手計算できる中間値で代替する。
