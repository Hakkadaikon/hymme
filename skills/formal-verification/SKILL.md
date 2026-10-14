---
name: formal-verification
description: >
  雑な仕様を Lean 4 の形式仕様へ落とし込み、証明で検証し、そこから test-first で実装へ繋ぐワークフロー。
  ユーザーが「形式検証」「formal verification」「FV」「証明したい」「不変条件を保証」「Lean で書いて」
  「仕様を形式化」と言ったとき、またはアルゴリズム・プロトコル・セキュリティ性質の正しさを
  数学的に保証したいときに使用する。autoformalization と proof repair のループを回す。
user-invocable: true
argument-hint: "[証明したい性質/仕様(ファイルパス or 説明)]"
---

# Formal Verification (Lean 4)

雑な要件を形式仕様にし、証明支援系で網羅的に検証し、test-first 実装へ繋ぐ。LLM が戦略を立て、Lean が厳密に検証するハイブリッド。証明が通った性質だけが「保証された」と言える。

## superpowers ワークフロー上の位置

- **superpowers:brainstorming の Architectural パス**で、アプローチ確定後・spec 確定前に §1 の性質カタログを作る(critical なアルゴリズム・セキュリティ性質があるときだけ)。設計の検証であり実装行為ではない(成果物は git 管理外の `tasks/fv/`)。証明済み性質は spec の要件・受け入れ条件に**手法名なしで**入れる(「Lean で証明した」とは書かない。[`../_shared/stealth-artifacts.md`](../_shared/stealth-artifacts.md))。
- **重い証明はコントローラが hymme:prover へ dispatch する。** prover は検証ワーカー: `tasks/fv/` に成果物を残し、コミットせず、レビュアーを自分で呼ばない。superpowers:subagent-driven-development の implementer に証明をさせない。
- **§4 の橋渡しテストは plan の Task になる**(test-design 経由で T-ID 化し、superpowers:writing-plans の「Write the failing test」に落とす)。実装は implementer が superpowers:test-driven-development で書く。

## 前提ツール

`elan`(flake の tools に含む)が入っていること。なければ `nix profile install .#skill-tools`。

- `elan`：Lean toolchain manager。`lake` / `lean` を供給する。
- 初回のみ `elan default stable` で Lean 4 本体を入れる(これをやるまで `lake` は "no default toolchain" で落ちる)。
- 新規プロジェクト: `lake new <name> math`(Mathlib 付き)or `lake new <name>`(素)。Mathlib は重い。roundtrip / 範囲 / 単射性 / 状態機械程度なら素の `Init`/`Std` で足り、`lake build` も速い。**本当に必要になるまで Mathlib を足さない**(YAGNI)。
- ビルド/証明チェック: `lake build`。エラーが証明の穴。

**プロジェクト構造の罠**: `lake new Foo` はルート直下の `Foo.lean`(ライブラリルート)と `Foo/Basic.lean`(実体)を作る。ビルド連鎖は `Foo.lean` が `import Foo.Basic` で `Foo/Basic.lean` を引く。**証明は `Foo/Basic.lean`(サブディレクトリ側)に書く**。ルート直下にうっかり別の `Basic.lean` を置くとビルド対象外になり「証明したのにビルドに反映されない」事故になる(実際に起きた)。新モジュールを足すときは `Foo.lean` に `import Foo.<Mod>` を必ず追記する。

**実行時の罠**: サンドボックス等では `export ELAN_HOME="${ELAN_HOME:-$HOME/.elan}"` と `export TMPDIR="${TMPDIR:-/tmp}"` を `lake build` の前に。これが無いと toolchain 解決や一時ファイルでこける。

未導入なら導入を促し、勝手に大規模インストールしない。

## ワークフロー

順に進む。各段で止まって検証する。

### 1. 仕様を網羅形式へ

雑な NL 要件 → 構造化(precondition / invariant / postcondition / 想定する脅威)。曖昧な点は実装前にユーザーに確認する。「全ケース」を意識する: 空入力、境界、重複、順序。

**検証対象を数学的性質で止めない。** 単純な指示だと、roundtrip・involution・単射性のような「数式に見える」所だけ形式化して終わりがち。だがプロトコル・状態機械・並行処理では、形式検証の本丸はむしろ次にある。観点を分けて性質を網羅的に洗い出してから形式化に入る:

- **状態機械の不変条件**: 状態は単調にしか進まない / 吸収状態から出ない / 不正状態に到達しない。
- **MUST / MUST NOT**: 仕様の規範文言(RFC の MUST/SHALL/MUST NOT)を1つずつ述語にする。「拒否すべき入力は必ず拒否される」「全入力は accept か reject に決定的に分類される(網羅性)」。
- **temporal(時間的)性質**: 順序保存・応答義務・到達可能性・収束。「X を受けたら必ず Y を返す」「両者が同時に動いても収束する」。状態遷移やプロトコルがあるのに temporal を1つも書いていないなら、たぶん見落としている。
- **脅威(STRIDE)**: 信頼境界(外部入力・認証・権限)があるなら、なりすまし・改ざん・否認・情報漏洩・サービス拒否・権限昇格の6観点で「攻撃者がこう入力しても性質は保たれる」を立てる。例: 未認証の入力では権限の要る状態へ遷移しない(権限昇格)、どんな入力列でも資源消費が上限を超えない(サービス拒否)。
- **ワークフロー全体**: 個々のステップだけでなく、ハンドシェイク→データ→クローズのような筋全体が仕様通りか。

性質を洗い出すときの原則は **過剰抽出は安全、漏れは危険**。要らない性質を挙げても後で「優先度低」「対象外」に落とせばよく、コストは選別の手間だけだ。だが挙げ損ねた性質は形式化も証明もされず、通常テストをすり抜ける。だから迷ったらカタログに載せる方へ倒す。

仕様書(RFC・標準・設計文書)があるなら、上の観点別に**性質カタログ**を作る(ID・性質・出典・観点・型・優先度の表。観点は上の5つのどれ由来か)。それを埋めてから Lean へ。数学的核(既証の補題)は、カタログ中の該当性質の「根拠」として再利用する(例: 単射性の補題が「非正規表現を拒否する」性質の土台になる)。

### 2. Lean に形式化(autoformalization)

NL → Lean の `def` + `theorem`。例: 「ソートは要素を保存し、順序付ける」を 2 theorem に対応させる → [references/formalization-examples.md](references/formalization-examples.md)。

`sorry` で穴を明示してから埋める。型エラー・証明失敗のメッセージを次の段にフィードバックする。

**状態機械・temporal 性質の形式化**(§1 で洗い出した非数学的性質はここで形式化する):

- **決定的 step 関数**にする。`step : State → Input → (State × Output)` を定義し、不変条件を「step の単一ステップ性質」として証明する。網羅性(全入力が accept か reject に分かれる)・単調性(状態が逆行しない)・吸収性はここで落ちる。例(単調性・error→closed の一方向性)は [references/formalization-examples.md](references/formalization-examples.md)。
- **temporal 性質は trace 述語**にする。イベント列を `List Event` で表し、順序・応答義務・収束を List 上の述語/関数で証明する。チャンク分割非依存(`flatten` 不変)、メッセージ境界保存(encode/decode roundtrip)、race 収束(`f (f s) = terminal`)など。例(チャンク分割非依存)は [references/formalization-examples.md](references/formalization-examples.md)。
- **応答義務に層がある場合は「層注」を明示**する。たとえば「ping に pong を返す」のうち、ライブラリは ping を欠落なく通知する所まで保証し、pong 送信はアプリ責務、という切り分けがあるなら、証明対象を「通知の正確さ」に限定し、境界を仕様にも証明コメントにも書く。嘘の全体保証をしない。

### 3. 証明(proof repair ループ)

- `lake build` で現在の証明状態とエラーを観察。
- tactic を提案 → 実行 → 結果を見る。失敗したら lemma 追加 or 戦略変更。
- 自動化を使う: `simp` / `omega` / `decide` / `exact?` / `apply?`。Mathlib があれば `exact?` で既存補題を探す。
- 1 証明が重いなら補題に分解する。
- **`sorry` を埋める前に、定義(`def`)が証明できる形かを先に確かめる**。型がそもそも通らない定義は証明以前に直す。よくある罠は `Bool`(`&&`/`||`)と `Prop`(`∧`/`∨`)の混在で、判定述語を書くときに起きやすい。`decide (...)` を使う純 `Bool` 述語へ書き直して解消する。定義のシグネチャは実装(C/Rust 等)と1対1で対応させるため安易に変えないが、**証明の都合で本体を等価変形したらその理由を仕様/コメントに1行残す**。
- **埋まらない `sorry` は残さず明示する**。「ここは未証明」と報告する。嘘の `sorry` を通った証明と偽らない。
- **証明の真正性を `#print axioms <thm>` で確認する**。依存が標準 3 公理(`propext` / `Classical.choice` / `Quot.sound`)だけなら本物。`sorryAx` が出たら穴が残っている。`native_decide` はコンパイラを信頼基盤に加える(`Lean.ofReduceBool` 公理が増える)ので、カーネル検証で済むなら `decide` を使い、`native_decide` は避ける。「sorry 無しで通った」と「カーネルが本当に検証した」は別物だ。後者まで確認して初めて「保証された」と言える。

### 3.5 文面の往復確認

`sorry` 無し・標準公理だけで通っても、定理が要件と違うことを言っていれば(向きが逆・条件が弱い・前提が充足不能で空成立)何も保証しない。各定理の文面と、文面が参照する定義だけを独立した読み手に平文へ戻させ、性質カタログと突き合わせる。前提付きの定理は、前提を満たす具体例を `example` で示して空成立でないことを確かめる。手順と判定は [`../_shared/roundtrip-faithfulness.md`](../_shared/roundtrip-faithfulness.md)。読み手の dispatch はコントローラが行う(prover は入力ファイルを作るところまで)。全行が `full`(または理由付き `partial`)になるまで §2〜3 へ戻す。

### 4. test-first 実装へ橋渡し

**REQUIRED SUB-SKILL:** superpowers:test-driven-development(サイクルの基底)。hymme の差分は**性質テストをまず落として、モデルと実装の乖離を検出する**こと。形式仕様が「何をテストすべきか」を決め、証明済み性質はそのまま property-based test の述語になる。

- Lean 内で完結するなら `#eval` / `decide` でチェック、または code extraction。
- 別言語(Rust/TS 等)で実装するなら、各 theorem を1つの property test に対応させる。
- 出力: 証明済み性質の一覧 + 対応するテスト + 実装ガイド + 「形式的に保証された部分」の明示(spec には手法名なしで)。

**証明 ↔ 実装の乖離をテストで検出する(橋渡しの主目的)。** 証明したのは「モデル」であって実装そのものではない。証明した step 関数/述語の分岐を実装の対応する分岐に1対1で対応させ、各性質について実装挙動を観測するテストを書き、**まず落とす**(Red)。落ちなければ既存挙動を写しただけのテストで、乖離を検出していない。実装がモデルからズレていればここで落ちるので、実装をモデルに合わせて直す。緑で初めて証明と実装が一致したと言える。

この方式は実際に実装バグを炙り出す。モデルでは「クローズ受信後はデータを破棄」なのに実装が受理していた、検証すべき入力を無検証で通していた、といった乖離は、橋渡しテストが先に落ちることで発見される。乖離が出た事実と修正は、性質カタログの脇(`tasks/fv/`)に記録する。

## 成果物の置き場(デフォルトは裏方)

証明物(Lean プロジェクト・性質カタログ・`#print axioms` ログ)は `tasks/fv/` 配下で作り込み、git 管理に持ち込まない。
git 管理下のドキュメント・コミット・テストコメントに手法の存在を書かず、表に出すのは §4 の橋渡しテストと実装だけ。
明示オプトイン時の例外を含む詳細は [../_shared/stealth-artifacts.md](../_shared/stealth-artifacts.md)。

## 現実的な期待

- 完全自動は難しい。LLM が戦略、`simp`/`omega`/`exact?` で細部、複雑な所は人間レビュー。
- スケールしないときは critical な性質だけ形式検証する。残りは通常テスト。
- 証明探索はトークン/時間を食う。重い探索は補題に分け、コントローラが hymme:prover を並列 dispatch する(基底 superpowers:dispatching-parallel-agents。共有リソースの直列化・命名衝突・単体緑≠統合緑・成果物実在での進捗判定・外部ツールの sandbox 可否は [`../_shared/parallel-delegation.md`](../_shared/parallel-delegation.md))。
- 証明の都合で定義を等価変形したときの理由(Why not)はコメントに残す。コード/テスト/コミット/
  コメントの役割分担は [`../_shared/code-comment-commit-roles.md`](../_shared/code-comment-commit-roles.md) を参照。

## 完了前の必須ゲート(コンプライアンスレビュー)

証明が通ったと判断した直後、成果を「保証された」と報告する前、および橋渡しテストを完了扱いにする前に、**コントローラが** `hymme:formal-verification-reviewer` サブエージェントを dispatch して外側から検査させる。prover に委譲していた場合も prover は呼ばず、報告を受けたコントローラが呼ぶ。
渡すもの: 性質カタログと Lean ソースの場所、往復確認の入力ファイルと判定表、橋渡しテストと実行ログの場所、spec があればそのパス。
レビュアーが挙げた違反(`sorry` 残りの保証扱い、往復確認の未実施・`mismatch`/`vacuous` 残り、`#print axioms` 未確認や `sorryAx`/`native_decide` 依存、性質カタログの temporal 漏れ、橋渡しテストの欠落)を解消してから完了とする。「ビルドが通った」を「カーネルが検証した」の代わりにしない。

## やらないこと

- 通った証明だけを「保証」と呼ぶ。`sorry` 入りを保証扱いしない。
- 形式化が目的化しない。実装が要らない検証はやらない(YAGNI)。
- 小さく始める。1ツール・1仕様の例が回ってから広げる。
- **「巨大だから対象外」と自分で性質のスコープを縮めない。** 依存先の仕様も調べて性質カタログに載せる(過剰抽出は安全・漏れは危険)。大きい証明は補題に MECE 分割して順に積む。分割はスコープ除外ではない。critical なのに「別領域だから」と落とすのは禁止。落とすならカタログに理由を1行残す。
- **公式定数・テストベクタを外部検索の鵜呑みで証明/テストに焼かない。** XOR・長さ・オフセットなど手計算できる部分は自分で再計算して裏取りする(検索結果の hex を信用しない)。フルベクタが取れないなら round-trip + 構成要素の既知ベクタ + 手計算できる中間値で代替する。
