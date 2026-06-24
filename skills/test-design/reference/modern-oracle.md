# 期待値を別の参照や関係で代替するテスト

期待値そのものを1つずつ手で書けないとき、別の参照や関係に「正しさの判定」を委ねるテスト群。
古典のブラックボックス技法が「この入力でこの出力」を1つずつ固定するのに対し、ここでは正解を直接持たないまま、信頼できる別の基準や関係との突き合わせで合否を決める。

これらは **oracle 問題**(期待値をどう用意するか)への異なる解として読むと筋が通る。
過去の出力を基準に固める(スナップショット、承認)、別の信頼できる実装と突き合わせる(差分)、入力と出力の関係で縛る(メタモルフィック)、抽象モデルを oracle に据える(モデルベース)、上流の形式手法で確立した述語を実装にぶつける(形式検証連携)という、参照の取り方の違いで整理する。

## 目次

- [ゴールデンテスト/スナップショットテスト](#ゴールデンテストスナップショットテスト)
- [承認テスト(Approval Testing)](#承認テストapproval-testing)
- [差分テスト(Differential Testing)](#差分テストdifferential-testing)
- [メタモルフィックテスト(Metamorphic Testing)](#メタモルフィックテストmetamorphic-testing)
- [モデルベーステスト(Model-Based Testing)](#モデルベーステストmodel-based-testing)
- [形式検証連携(TLA+/Lean → 述語テスト)](#形式検証連携tlalean--述語テスト)

---

## ゴールデンテスト/スナップショットテスト

### 概要
出力を初回に「ゴールデン(基準)」として保存し、以降は現在の出力との差分で合否を判定する。

### 目的/いつ使う
レンダリング結果、整形出力、コード生成、大きな構造体など、期待値を手で書くより一度確定させて固定したいときに使う。
差分が出たら、バグか意図した変更かを人が判断し、後者なら基準を更新する。
出力が非決定的(時刻、乱数、順序不定)なものは正規化しないと毎回壊れるので、その前処理が無いなら使わない。

### TypeScript example
整形関数の出力をスナップショットに固定する。

```ts
import { describe, it, expect } from "vitest";
import { renderInvoice } from "./invoice";

describe("renderInvoice: snapshot", () => {
  it("matches the golden output", () => {
    const out = renderInvoice({ id: 7, items: [{ name: "pen", qty: 3 }] });
    expect(out).toMatchSnapshot();
  });
});
```

### 落とし穴
- 差分を読まずに `--update` で機械的に承認すると、バグごと基準を上書きする。更新は必ず差分を見てから行う。
- 巨大スナップショットは差分が読めず形骸化する。意味のある単位に分けるか、要点だけを固定する。

### 網羅の定義
- **網羅基準**：網羅対象(レンダリング、整形、生成の代表入力集合)それぞれにゴールデンが存在し、現出力との差分がゼロ。
- **網羅手順**：
  1. 代表入力を同値分割で選ぶ。
  2. 各出力をスナップショットに固定する。
  3. 差分が出たらバグか意図変更かを人が判断する。
- **達成チェック**：非決定要素(時刻、乱数、順序)を正規化済みか確認する。巨大スナップショットで差分が読めず形骸化していないかを見る。

---

## 承認テスト(Approval Testing)

### 概要
スナップショットの一般形。
出力(テキスト、画像、任意の成果物)を「承認済み」ファイルとして保持し、現在の出力と突き合わせ、差分を専用のビューアで人がレビューして承認する。

### 目的/いつ使う
レガシーコードの現状を素早く固定して安全網を張りたいとき(characterization test)や、複雑な成果物を都度レビューで通したいときに使う。
判定基準は「人が見て OK と言った状態との一致」なので、仕様が未文書でも始められる。
仕様が明確で期待値を直接書けるなら、承認の往復を挟まずアサーションで書くほうが速い。

### TypeScript example
承認ツール(例: `approvals`)に成果物を渡す。初回は `received` を生成し、人が `approved` にリネーム/承認して基準化する。

```ts
import { describe, it } from "vitest";
import { verify } from "approvals/lib/Providers/Jest/JestApprovals";
import { generateReport } from "./report";

describe("generateReport: approval", () => {
  it("matches approved report", () => {
    // 差分があれば received と approved を並べて提示し、人が承認するまで失敗
    verify(generateReport({ region: "jp", year: 2026 }));
  });
});
```

### 落とし穴
- 承認の主体が曖昧だと「とりあえず承認」が横行し、基準が腐る。誰が何を見て承認したかを運用で担保する。
- 非決定的出力はスナップショット同様、承認前に正規化(日時や ID のマスク)が要る。

### 網羅の定義
- **網羅基準**：網羅対象の各成果物に承認済み版があり、現在の出力と一致する。
- **網羅手順**：
  1. 対象成果物を列挙する。
  2. received を生成する。
  3. 人がレビューし approved 化する。
- **達成チェック**：承認の主体と根拠が運用で担保されているか、非決定要素をマスク済みかを確認する。レガシー固定(characterization)では現状の振る舞い集合を網羅対象に取る。

---

## 差分テスト(Differential Testing)

### 概要
同じ入力を信頼できる別実装(参照実装、旧版、別ライブラリ)にも流し、両者の出力が一致するかで判定する。

### 目的/いつ使う
期待値を自前で書けないが、正しいと信じられる別実装があるとき(最適化版と素朴版、自作と標準ライブラリ、移植元と移植先)に使う。
oracle 問題を「もう一つの実装」で解くのが本質。
参照実装が無い、あるいは両実装が同じ前提で同じ間違いをし得るなら、一致しても正しさの保証にならない。

### TypeScript example
最適化版 `fastSum` を、素朴な参照実装と任意入力で突き合わせる(PBT と組み合わせると強い)。

```ts
import { describe, it, expect } from "vitest";
import fc from "fast-check";
import { fastSum } from "./fast-sum";

const refSum = (xs: number[]) => xs.reduce((a, b) => a + b, 0);

describe("fastSum: differential vs reference", () => {
  it("agrees with the naive implementation on any int array", () => {
    fc.assert(
      fc.property(fc.array(fc.integer()), (xs) => {
        expect(fastSum(xs)).toBe(refSum(xs));
      }),
    );
  });
});
```

### 落とし穴
- 両実装が同じ仕様の穴(同じ丸め誤差、同じ未定義動作の解釈)を共有すると、一致してもバグは残る。独立性が命。
- 浮動小数は厳密一致しないことがある。許容誤差での比較に切り替える。

### 網羅の定義
- **網羅基準**：信頼できる参照実装と、入力空間を代表する入力集合(PBT 併用で多数)で全件一致する。
- **網羅手順**：
  1. 参照実装を用意する。
  2. 同じ入力を両者へ流す。
  3. 出力一致を assert し、PBT で入力を広く取る。
- **達成チェック**：両実装が同じ穴を共有していないか(独立性)を確認する。浮動小数は許容誤差で比較する。

---

## メタモルフィックテスト(Metamorphic Testing)

### 概要
単一入力の正解が分からなくても、「入力をこう変換したら出力はこう変わる(変わらない)はず」という関係(metamorphic relation)で検証する。

### 目的/いつ使う
oracle が無い対象(検索ランキング、数値計算、機械学習推論、最適化)で有効である。
正解そのものではなく入力変換と出力の関係を縛るので、期待値を一切用意せずに矛盾を炙り出せる。
出力の絶対値を直接アサートできるなら、わざわざ関係に置き換える必要はない。

### TypeScript example
ソートの metamorphic relation: 入力を並べ替えても出力は不変、長さも不変。

```ts
import { describe, it, expect } from "vitest";
import fc from "fast-check";
import { sortAsc } from "./sort";

describe("sortAsc: metamorphic relations", () => {
  it("output is invariant under input permutation and preserves length", () => {
    fc.assert(
      fc.property(fc.array(fc.integer()), (xs) => {
        const shuffled = [...xs].reverse();
        expect(sortAsc(shuffled)).toStrictEqual(sortAsc(xs));
        expect(sortAsc(xs)).toHaveLength(xs.length);
      }),
    );
  });
});
```

### 落とし穴
- 関係が弱いと(長さ不変だけ等)中身が壊れていても通る。複数の関係を重ねて締める。
- 思い込みの関係(本当は成り立たない)を入れると偽陽性を量産する。関係の根拠は仕様に置く。
- 数値の関係(可換、結合、分配)を等価で確かめるとき、`toBe`(`Object.is`)は `-0` と `+0` を別物と判定して flaky に落ちる。たとえば分配法則の左辺が `-0`、右辺が `+0` になると、関係は成り立っているのに失敗する。数値の関係比較には `===` か許容誤差を使う(PBT と同じ罠。`modern-generative.md` の落とし穴参照)。

### 網羅の定義
- **網羅基準**：対象に成り立つ metamorphic relation 集合を全て検査し、各 relation が広い入力で破れない。
- **網羅手順**：
  1. 入力変換と出力変化の関係を仕様から複数導く。
  2. 各関係を property 化する。
  3. 広い生成器で多数試行する。
- **達成チェック**：関係が弱すぎ(長さ不変だけ等)て中身の破れを見逃さないか確認する。各関係の根拠が仕様にあるか、複数関係を重ねて締めているかを見る。

---

## モデルベーステスト(Model-Based Testing)

### 概要
システムの振る舞いを抽象モデル(状態機械など)で表し、そこからテスト系列(操作の列)を自動生成して実システムと突き合わせる。

### 目的/いつ使う
操作の順序や履歴に依存する対象(プロトコル、ステートフルな API、UI フロー、データ構造)で、人手では思いつかない操作列を網羅したいときに使う。
モデル側を oracle として、各操作後にモデルと実装の状態が一致するかを判定する。
状態も順序も無い純粋関数には過剰。通常の PBT で足りる。

### TypeScript example
fast-check の `commands`(ステートフル PBT)で、モデルと実装を操作列で並走させる擬似コード。

```ts
// model: 期待される振る舞いの最小実装(oracle)
// real:  テスト対象(例: LRU キャッシュ)
// fast-check が put/get の操作列をランダム生成し、各操作後に invariant を照合する
fc.assert(
  fc.property(fc.commands([PutCommand(), GetCommand()]), (cmds) => {
    const model = { map: new Map() };          // 参照モデル
    const real = newCache();                   // 実装
    fc.modelRun(() => ({ model, real }), cmds); // 各 Command の check/run で両者を比較
  }),
);
```

### 落とし穴
- モデルが実装と同程度に複雑だと、モデル自身がバグの温床になり oracle の信頼が崩れる。モデルは意図的に素朴に保つ。
- 操作列が長くなると失敗の再現と最小化が重い。shrink が効く範囲に操作を絞る。

### 網羅の定義
- **網羅基準**：モデル(状態機械)から生成した操作列で、到達したモデル状態と遷移を網羅し、各操作後にモデルと実装が一致する。
- **網羅手順**：
  1. 抽象モデルを定義する。
  2. `fast-check` の commands 等で操作列を生成する。
  3. 各操作後に invariant を照合する。
- **達成チェック**：モデルが素朴に保たれ oracle の信頼が崩れていないか確認する。操作列が長すぎて shrink が効かなくないかを見る。

---

## 形式検証連携(TLA+/Lean → 述語テスト)

### 概要
上流の形式手法で確立した不変条件や証明済み述語を、そのまま実装に対する property-based test の property として叩き、設計とコードの間を埋める。

### 目的/いつ使う
設計や数学的性質を形式手法で固めた後、その性質が実装でも成り立つことを継続的に確かめたいときに使う。
このリポジトリの姉妹スキルと接続する:

- `loop-engineering`(TLA+ で状態遷移、並行、プロトコルの設計を網羅検査し、反例を Gherkin の受け入れ仕様へ落とす)。
  TLA+ の安全性不変条件(例: 「同時にロックを保持するのは高々1者」)を、実装の操作列に対する property として再表現する。
  反例から生まれた Gherkin シナリオは、そのまま具体例のテストになる。
- `formal-verification`(Lean 4 でアルゴリズムやセキュリティ性質を証明)。
  Lean で証明した定理(例: `decode (encode x) = x`、入力検証の健全性、分類の網羅性)を、PBT の property として実装に対して走らせる。

形式手法は性質が「数学的に正しい」ことを保証するが、その性質が**目の前の実装で**成り立つかは別問題。
PBT はその橋渡し層であり、証明済み述語を実装にぶつけて乖離を検出する。
TLA+/Lean を回していない素のロジックに、わざわざこの連携を持ち込む必要はない(YAGNI)。

### TypeScript example
Lean で証明済みの述語「decode は encode の左逆元」を、実装に対する property としてそのまま叩く。

```ts
import { describe, it, expect } from "vitest";
import fc from "fast-check";
import { encode, decode } from "./codec";

// Lean で証明済み: ∀ x, decode (encode x) = x
// 同じ述語を実装に対する property として実行し、設計と実装の乖離を検出する
describe("codec: bridges the proven invariant", () => {
  it("decode is a left inverse of encode (proven in Lean)", () => {
    fc.assert(
      fc.property(fc.jsonValue(), (x) => {
        expect(decode(encode(x))).toStrictEqual(x);
      }),
    );
  });
});
```

### 落とし穴
- 形式モデルと実装の型や粒度がずれると、同じ名前でも別の性質を検査してしまう。述語の対応を1対1で明記する。
- 証明済みだからとテストを省くと、モデルに無い実装上の前提(I/O、並行、リソース)が抜ける。橋渡しテストは省略しない。

### 網羅の定義
- **網羅基準**：上流(TLA+/Lean)で確立した不変条件と証明済み述語を全て実装への property として叩き、乖離ゼロ。
- **網羅手順**：
  1. TLA+ の安全性不変条件と Lean の定理を列挙する。
  2. 各述語を実装の操作列や入力に対する property へ1対1で写す。
  3. 反例由来の Gherkin を具体例テストにする。
- **達成チェック**：モデルと実装で型や粒度がずれて別性質を検査していないか確認する。証明済みでも橋渡しテストを省かない。

---

ランダム入力を生成して性質や頑健性を叩く系(PBT、ファジング、コンビナトリアル)は [modern-generative.md](modern-generative.md) にまとめた。
