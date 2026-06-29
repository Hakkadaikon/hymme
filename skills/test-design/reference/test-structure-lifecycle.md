# テストの構成パターン(ライフサイクルとデータ供給)

テスト一本の周辺、すなわち確保したリソースの後始末と、検証対象に渡すデータの組み立て方の型をまとめる。
出典は t-wada(和田卓人)の TDD 観点、および xUnit Test Patterns の語彙。

このファイルはリソースの**ライフサイクル**(setup/teardown)とテストデータの**供給**(Builder / Object Mother)を扱う。
テスト本体の内部構成(Arrange/Act/Assert などの段の切り方)は [`test-structure-anatomy.md`](test-structure-anatomy.md) を参照。
「良いテストとは何か」の規範は [`good-test-principles.md`](good-test-principles.md)、テストダブルの使い分けは [`test-doubles.md`](test-doubles.md) を参照。

各項目は「概要」「目的/いつ使う」「TypeScript example(vitest 想定)」「落とし穴」「遂行手順」「完了チェック」「網羅とのつなぎ方」の構成で示す。

## 目次

- [Four-Phase Test(setup / exercise / verify / teardown)](#four-phase-testsetup--exercise--verify--teardown)
- [Test Data Builder / Object Mother](#test-data-builder--object-mother)

---

## Four-Phase Test(setup / exercise / verify / teardown)

### 概要
テスト本体を、準備(**setup**)、実行(**exercise**)、検証(**verify**)、後始末(**teardown**)の四段に分ける構成。
AAA([`test-structure-anatomy.md`](test-structure-anatomy.md))に後始末の段を明示的に足した型である。

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
- teardown を書き忘れると、確保したリソースが次のテストへ漏れ、テスト間で状態が汚染される。実行順に依存して落ちる flaky の温床になる(テスト間順序・状態漏れの検出と封じ込めは [`flakiness-concurrency.md`](flakiness-concurrency.md) を参照)。
- `afterEach` で例外が出ると後続の片付けが止まることがある。解放処理は失敗しても次へ進むよう書く。

### 遂行手順(着手→完了)
Four-Phase で書く作業の本体は「確保するリソースごとに解放を対で書き、setup/teardown を本体の外へ追い出す」ことだ。次の順で進める。

1. **解放が要るリソースを列挙する**:DB 接続・一時ファイル・外部プロセス・ソケットなど、確保したら必ず手放すものを書き出す。1つも無ければ AAA で足り、この型は過剰(YAGNI)。
2. **確保と解放を対で先に書く**:列挙した各リソースについて、`beforeEach` の確保(`open`)と `afterEach` の解放(`close`)を先にペアで置く。確保を書いた瞬間に対の解放を書く(後回しが漏れの原因)。
3. **初期状態を毎回そろえる**:`beforeEach` で各テストが同じ初期状態から始まるようにする。前テストの残骸が見えるなら setup が初期化し切れていない。
4. **exercise / verify を本体に AAA で書く**:テスト本体には実行(exercise)と検証(verify)だけを残し、AAA の Act/Assert と同じ規律(1操作・1関心)を守る。setup/teardown を本体に書かない。
5. **teardown を例外耐性にする**:解放処理は途中で1つ失敗しても残りが走るよう書く(`try`/`finally` か個別 `catch`)。1つの解放失敗で後続の片付けが止まると次テストへ状態が漏れる。
6. **順序非依存を確認する**:テスト順をシャッフルして走らせ([`flakiness-concurrency.md`](flakiness-concurrency.md))、緑のままなら setup/teardown が状態を正しく閉じている。

### 完了チェック(もれ確認)
- **確保と解放が対か**:`grep -nE "beforeEach|afterEach" <test>` で、`beforeEach` の各確保に対応する `afterEach` の解放があるか。片側だけならリソース漏れ。
- **本体に足場が無いか**:exercise/verify のブロックに setup/teardown 相当の確保・解放が紛れていないか(紛れていれば段の分離が崩れている)。
- **teardown が例外耐性か**:`afterEach` 内が、途中の失敗で後続解放を止めない構造(`finally`/個別 `catch`)になっているか。
- **シャッフルで緑か**:`vitest --sequence.shuffle` 等で順序を入れ替えても緑か。落ちれば状態漏れ。
- **そもそも teardown が要るか**:解放対象が無いのにこの型を使っていないか(純計算なら AAA で十分)。

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
テストデータをどこまで本物に寄せるか、どこを既定値で隠すかの方針は [`strategy-operations.md`](strategy-operations.md) のテストデータ戦略に従う。

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

### 遂行手順(着手→完了)
Builder/Object Mother を入れる作業の本体は「既定値を1か所に集め、各テストが結果に効く差分だけを上書きする形へ寄せる」ことだ。次の順で進める。

1. **準備の肥大を確認する**:複数テストの Arrange に、同じオブジェクト組み立てが繰り返され、各テストは一部フィールドしか気にしていない状態か確認する。そうでないなら導入しない(YAGNI、AAA の直書きで足りる)。
2. **妥当な既定値を1か所に決める**:そのオブジェクトの「ごく普通の1個体」を既定値として定義する(`{ name, role: "viewer", active: true }`)。既定値は本番のバリデーションを通る正常値にする。
3. **差分の上書き口を `with…` で開ける**:Builder は各フィールドに `withRole` `inactive` のようなチェーンメソッドを持たせ、`build()` で複製を返す。値を詰めるだけにし、計算・検証は一切書かない(書くと本番の写経になる)。
4. **定番が複数テストで共有されるなら Object Mother**:「期限切れの注文」のような名前付き定番を複数テストで使い回すなら Object Mother で1関数にまとめる。1テスト固有の差分は Builder の `with…` 側へ寄せる。
5. **テスト本体に差分だけ残す**:各テストは `aUser().withRole("admin").build()` のように、結果に効くフィールドだけを書く。既定値は本体に出さない(何が効くかがテストから読める状態にする)。
6. **既定値は本番経路で作れないか先に疑う**:本番にファクトリ/コンストラクタがあるなら Builder の内側からそれを呼び、テスト用に組み立てロジックを二重持ちしない。

### 完了チェック(もれ確認)
- **Builder にロジックが無いか**:Builder/Mother の本体に計算・分岐・バリデーションが無いか(値の代入だけか)。あれば本番との乖離源。
- **本体に差分だけ残ったか**:各テストの組み立てが `with…` の差分指定だけになり、既定値の全フィールドを書き並べていないか。
- **既定値が正常値か**:既定で `build()` したオブジェクトが本番の検証を通る妥当な値か(壊れた既定だと全テストが前提から崩れる)。
- **Mother が肥大していないか**:Object Mother の定番が増殖して、どのフィールドが効くか読めなくなっていないか。効くフィールドを見せたいテストは Builder へ寄せる。
- **そもそも必要か**:導入で行が減ったか。1〜2テストにしか使わないなら直書きの方が短い(YAGNI)。

### 網羅とのつなぎ方
Builder と Object Mother は、各振る舞いに対応するテストへ前提データを供給する足場であって、それ自体が網羅対象ではない。
網羅は依然として振る舞いの集合に対して数え、Builder はその振る舞いを際立たせる差分(`withRole("admin")` など)だけをテスト本体に残す役を負う。
差分が明示されていれば、どの入力区分(同値クラス)を踏んだ振る舞いかがテストから読め、網羅の対応づけが崩れない。

---

テスト本体の内部構成(AAA / Given-When-Then / テーブル駆動)は [`test-structure-anatomy.md`](test-structure-anatomy.md) を参照。
TDD の進め方(駆動のサイクルと戦略)は [`tdd-cycle.md`](tdd-cycle.md) を参照。
