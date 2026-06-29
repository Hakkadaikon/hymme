# テストの構成パターン

個々のテストを、本体の中でどう構成するかの型をまとめる。
テスト一本の内部を、準備、実行、検証の段に切り分ける配置の規範であり、どんな順序で実装を駆動するかとは別の話題である。
出典は t-wada(和田卓人)の TDD 観点。

「良いテストとは何か」の規範は [`good-test-principles.md`](good-test-principles.md)、テストダブルの使い分けは [`test-doubles.md`](test-doubles.md) を参照。

各項目は「概要」「目的/いつ使う」「TypeScript example(vitest 想定)」「落とし穴」の構成で示す。

## 目次

- [AAA パターン(Arrange-Act-Assert)](#aaa-パターンarrange-act-assert)
- [Given-When-Then(BDD 由来)](#given-when-thenbdd-由来)
- [テーブル駆動 / パラメタライズドテスト(Table-Driven / Parameterized)](#テーブル駆動--パラメタライズドテストtable-driven--parameterized)
- [Four-Phase Test(setup / exercise / verify / teardown)](#four-phase-testsetup--exercise--verify--teardown)
- [Test Data Builder / Object Mother](#test-data-builder--object-mother)

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

## テーブル駆動 / パラメタライズドテスト(Table-Driven / Parameterized)

### 概要
同じ構造の入力と期待値の組を表(ケース配列)に並べ、1本のテスト定義で全行を回す構成。
行を増やすだけでケースを足せる。

### 目的/いつ使う
同じ操作を入力違いで何度も検証するときに使う。
同値分割の代表値や境界値分析の境界点は、本来この形で実装される([`blackbox-systematic.md`](blackbox-systematic.md) の `it.each` 例がそのまま当てはまる)。
分岐そのものが入力ごとに違う(値ごとに別経路をたどる)ときは、一表に押し込めず手法を見直す。

### TypeScript example
```ts
import { describe, it, expect } from "vitest";
import { classifyAge } from "./age";

describe("classifyAge: table-driven", () => {
  const cases = [
    { partition: "child", value: 5, expected: "child" },
    { partition: "adult", value: 30, expected: "adult" },
    { partition: "senior", value: 70, expected: "senior" },
    { partition: "invalid", value: -1, expected: "invalid" },
  ] as const;

  it.each(cases)("$partition ($value) -> $expected", ({ value, expected }) => {
    expect(classifyAge(value)).toBe(expected);
  });
});
```

### 落とし穴
- ケース名が静的だと、失敗時にどの行で落ちたか分からない。`$value` や `$partition` で行ごとに動的なラベルを付ける。
- ループ内に `if` で分岐を入れ、行ごとに違う検証をすると、一表が実質複数テストになり一テスト一振る舞いが崩れる。検証が割れるなら表を分ける。

### 網羅とのつなぎ方
テーブル駆動は、同値分割や境界値で出した代表値の一覧を、そのまま行に写す実装形である。
網羅すべき集合はケース配列の行の集合であり、抽出した代表値の数と行数が一致して初めて網羅が数えられる。
行ごとに動的ラベルを付けておくと、どの代表値が緑かを失敗出力から逆引きでき、網羅の達成度を行単位で追える。

---

## Four-Phase Test(setup / exercise / verify / teardown)

### 概要
テスト本体を、準備(**setup**)、実行(**exercise**)、検証(**verify**)、後始末(**teardown**)の四段に分ける構成。
AAA に後始末の段を明示的に足した型である。

### 目的/いつ使う
DB 接続、一時ファイル、外部プロセスなど、確保したリソースを使い終わったら必ず解放する必要があるときに使う。
setup と teardown を `beforeEach`/`afterEach` に置けば、各テストが同じ初期状態から始まり、終了時に必ず片付く。
解放するものが無い純粋な計算の検証なら AAA で足り、teardown 段は不要。

### TypeScript example
```ts
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { TempStore } from "./tempStore";

describe("TempStore", () => {
  let store: TempStore;

  beforeEach(async () => {
    store = new TempStore(); // setup: リソース確保
    await store.open();
  });

  afterEach(async () => {
    await store.close(); // teardown: 必ず解放
  });

  it("persists a value", async () => {
    await store.put("k", "v"); // exercise
    expect(await store.get("k")).toBe("v"); // verify
  });
});
```

### 落とし穴
- teardown を書き忘れると、確保したリソースが次のテストへ漏れ、テスト間で状態が汚染される。実行順に依存して落ちる flaky の温床になる(テスト間順序・状態漏れの検出と封じ込めは [`test-flakiness.md`](test-flakiness.md) を参照)。
- `afterEach` で例外が出ると後続の片付けが止まることがある。解放処理は失敗しても次へ進むよう書く。

### 網羅とのつなぎ方
Four-Phase は AAA と同じく一テスト一振る舞いを保つ型で、網羅の数え方は AAA と変わらない。
setup/teardown は振る舞いそのものではなく前後の足場なので、verify が担う一つの振る舞いだけを網羅対象として数える。
teardown が漏れて状態が漏れると、テストが互いに干渉し、本来独立に数えられるはずの各振る舞いの緑が信用できなくなる。

---

## Test Data Builder / Object Mother

### 概要
複雑なフィクスチャ(検証対象に渡すオブジェクト)の生成を、専用の構成要素に切り出す型。
**Builder** はメソッドチェーンで必要な差分だけを指定して組み立てる。
**Object Mother** は「典型的な管理者」「期限切れの注文」のような名前付きの定番データを返す。

### 目的/いつ使う
オブジェクトの組み立てに多くのフィールドが要り、各テストはそのうち一部だけを気にするときに使う。
Builder は、テストごとに効くフィールドだけを `with...` で上書きし、残りは既定値に任せる(何が結果に効くかがテスト本体から読み取れる)。
Object Mother は、複数テストで同じ定番データを使い回すときに使う。
テストデータをどこまで本物に寄せるか、どこを既定値で隠すかの方針は [`test-strategy.md`](test-strategy.md) のテストデータ戦略に従う。

### TypeScript example
```ts
import { describe, it, expect } from "vitest";
import { canAccessAdminPanel } from "./access";

// Builder: 既定値を持ち、差分だけ with... で上書きする
const aUser = () => {
  const user = { name: "alice", role: "viewer", active: true };
  const builder = {
    withRole: (role: string) => ((user.role = role), builder),
    inactive: () => ((user.active = false), builder),
    build: () => ({ ...user }),
  };
  return builder;
};

describe("canAccessAdminPanel", () => {
  it("allows an active admin", () => {
    expect(canAccessAdminPanel(aUser().withRole("admin").build())).toBe(true);
  });

  it("denies an inactive admin", () => {
    expect(canAccessAdminPanel(aUser().withRole("admin").inactive().build())).toBe(false);
  });
});
```

### 落とし穴
- Builder の中で本番の生成ロジック(計算やバリデーション)を真似て書くと、本番が変わったときに Builder だけ取り残され、テストが現実と乖離する。Builder は値を詰めるだけにし、ロジックは本番を呼ぶ。
- Object Mother に少しずつ違う定番を足し続けると肥大し、どのフィールドがそのテストの結果に効いているのか読み取れなくなる。効くフィールドを明示したいテストは Builder で差分指定へ寄せる。

### 網羅とのつなぎ方
Builder と Object Mother は、各振る舞いに対応するテストへ前提データを供給する足場であって、それ自体が網羅対象ではない。
網羅は依然として振る舞いの集合に対して数え、Builder はその振る舞いを際立たせる差分(`withRole("admin")` など)だけをテスト本体に残す役を負う。
差分が明示されていれば、どの入力区分(同値クラス)を踏んだ振る舞いかがテストから読め、網羅の対応づけが崩れない。

---

TDD の進め方(駆動のサイクルと戦略)は [tdd-workflow.md](tdd-workflow.md) を参照。
