# テストの構成パターン

個々のテストを、本体の中でどう構成するかの型をまとめる。
テスト一本の内部を、準備、実行、検証の段に切り分ける配置の規範であり、どんな順序で実装を駆動するかとは別の話題である。
出典は t-wada(和田卓人)の TDD 観点。

「良いテストとは何か」の規範は [`good-test-principles.md`](good-test-principles.md)、テストダブルの使い分けは [`test-doubles.md`](test-doubles.md) を参照。

各項目は「概要」「目的/いつ使う」「TypeScript example(vitest 想定)」「落とし穴」の構成で示す。

## 目次

- [AAA パターン(Arrange-Act-Assert)](#aaa-パターンarrange-act-assert)
- [Given-When-Then(BDD 由来)](#given-when-thenbdd-由来)

---

## AAA パターン(Arrange-Act-Assert)

### 概要
テスト本体を、準備(**Arrange**)、実行(**Act**)、検証(**Assert**)の三段に分ける構成。

### 目的/いつ使う
ほぼすべての単体テストで使える基本構成。
各段を空行で区切ると、何を準備し、何を実行し、何を確かめたかが一目で追える。
Act が複数行に膨らむのは、テスト対象の API が使いにくい兆候である。

### TypeScript example
```ts
import { describe, it, expect } from "vitest";
import { Cart } from "./cart";

describe("Cart", () => {
  it("sums line totals", () => {
    // Arrange
    const cart = new Cart();
    cart.add({ price: 100, qty: 2 });

    // Act
    const total = cart.total();

    // Assert
    expect(total).toBe(200);
  });
});
```

### 落とし穴
- Assert が複数の無関係な事柄を一度に検証し、一テスト一振る舞いの原則を崩す。
- Arrange が肥大して、何の準備が結果に効くのか読み取れなくなる。準備の核だけを残す。

### 網羅とのつなぎ方
AAA は、一テスト一振る舞いを保ち、網羅対象である振る舞いとテストを一対一に対応づける構成である。
この一対一が崩れると、何本書いたかと何を網羅したかがずれ、網羅の勘定が合わなくなる。
Assert に無関係な検証を詰め込むと、一本のテストが複数の振る舞いを曖昧に跨ぎ、振る舞い単位の網羅が数えられなくなる。
だから検証は、そのテストが担う一つの振る舞いに絞る。
Act が複数行に膨らむのは、一つの操作で一つの振る舞いを呼べていない兆候であり、網羅対象の切り方を見直す合図になる。
この一対一を保つと、リスト項目とテストが素直に対応し、網羅の達成度をテスト本数で追える。

---

## Given-When-Then(BDD 由来)

### 概要
AAA と同型の構成を、振る舞い駆動開発(BDD)の語彙で表す。
前提(**Given**)、操作(**When**)、結果(**Then**)の三段からなる。

### 目的/いつ使う
非技術者にも読める言葉で仕様を記述したいときに使う。
受け入れテストや、Gherkin 形式のシナリオと相性がよい。
構造は AAA と同じであり、語彙が業務寄りになる点だけが違う。

### TypeScript example
```ts
import { describe, it, expect } from "vitest";
import { applyDiscount } from "./discount";

describe("discount for members", () => {
  it("gives 10% off to members", () => {
    // Given a member and a 1000 yen item
    const member = { isMember: true };

    // When the discount is applied
    const price = applyDiscount(1000, member);

    // Then the price is reduced by 10%
    expect(price).toBe(900);
  });
});
```

### 落とし穴
- Given に業務上意味のない技術的詳細を詰め込み、シナリオとしての読みやすさを失う。
- When に操作を二つ以上入れ、どちらが結果を生んだか曖昧にする。

### 網羅とのつなぎ方
Given-When-Then は AAA と同型で、網羅対象を受け入れ基準や Gherkin シナリオの側に取る。
つまり網羅すべき集合は、受け入れシナリオの一覧であり、それを一シナリオ一テストへ写す。
シナリオを出すときも、同値分割や境界値で正常系、境界、異常系を出し切ってから書く。
When に操作を二つ以上入れると、どちらの振る舞いを網羅したかが曖昧になり、シナリオとテストの一対一が崩れる。
だから When は一操作に絞り、Then で一つの結果だけを確かめる。
全シナリオに対応するテストが緑になった時点を、受け入れ観点での網羅完了とみなす。

---

TDD の進め方(駆動のサイクルと戦略)は [tdd-workflow.md](tdd-workflow.md) を参照。
