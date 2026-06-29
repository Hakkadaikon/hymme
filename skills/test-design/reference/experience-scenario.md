# ブラックボックス設計技法: シナリオベース(業務フローから導く)

仕様の構造から機械的に導くのではなく、業務フローや利用の物語から欠陥を狙う非形式的な技法のうち、**フローを起点にするもの**を扱う。
経験・直感・乱数を起点にするもの(エラー推測、ランダムファジング、探索的、アドホック)は [`experience-heuristic.md`](experience-heuristic.md) を参照。

体系的(仕様ベース)な技法のうち入力空間の分割(同値分割、境界値、デシジョンテーブル)は [`blackbox-partition.md`](blackbox-partition.md) を、履歴と状態(状態遷移、CRUD/ライフサイクル)は [`blackbox-state.md`](blackbox-state.md) を、組合せの縮約のうち論理ベース(原因結果グラフ、クラシフィケーションツリー)は [`blackbox-cause-effect.md`](blackbox-cause-effect.md) を、因子被覆(ペアワイズ、直交表、T-way)は [`blackbox-covering.md`](blackbox-covering.md) を参照。
本格的な生成系ファジングや PBT は [`generative-property.md`](generative-property.md) / [`generative-fuzzing.md`](generative-fuzzing.md)、ゴールデン/承認/差分等の oracle 代替は [`oracle-snapshot.md`](oracle-snapshot.md)、メタモルフィック/モデルベース/形式検証連携は [`oracle-relational.md`](oracle-relational.md) を参照。

これらは体系的技法の網を補う仕上げであり、単独で網羅性を主張しない。
見つけた欠陥は体系的技法へ書き戻して資産化(回帰テスト化)する。

## 目次

- [ユースケーステスト(Use Case Testing)](#ユースケーステストuse-case-testing)
- [シナリオテスト(Scenario Testing)](#シナリオテストscenario-testing)
- [構文テスト(Syntax Testing)](#構文テストsyntax-testing)

---

## ユースケーステスト(Use Case Testing)

### 概要
アクターとシステムの相互作用の流れ(主成功シナリオと拡張/例外フロー)を1本ずつテストケースに写す。

### 目的/いつ使う
要件がユースケース記述で与えられ、エンドツーエンドの業務フローが正しく完結するかを確かめたいとき。
基本フローだけでなく代替フローと例外フローを各々ケース化する。
個々の関数の単体検証には粒度が粗すぎる。

### TypeScript example
「ログイン → カート追加 → 決済」の主成功フローと、在庫切れの例外フローをそれぞれ1ケースにする。

```ts
import { describe, it, expect } from "vitest";
import { Shop } from "./shop";

describe("purchase use case", () => {
  it("main success flow: login -> add -> checkout", () => {
    const shop = new Shop({ stock: { sku1: 1 } });
    shop.login("alice");
    shop.addToCart("sku1");
    expect(shop.checkout().status).toBe("completed");
  });

  it("extension: out of stock blocks checkout", () => {
    const shop = new Shop({ stock: { sku1: 0 } });
    shop.login("alice");
    expect(() => shop.addToCart("sku1")).toThrow(/out of stock/);
  });
});
```

### 落とし穴
- 主成功フローだけ書いて、例外フローや代替フローを落とす。価値はむしろ例外側にある。
- ステップを細かく検証しすぎて単体テストの寄せ集めになる。フローの完結を見る。

### 網羅の定義
ユースケース/シナリオは単独で網羅を主張せず、体系的技法の上に重ねる仕上げである。

- **網羅基準(いつ網羅完了とみなすか)**：対象ユースケースの主成功フローを1ケース、加えて全拡張フローと例外フローを各1ケース踏んだとき。
- **網羅手順(基準を満たすケース集合の作り方)**：
  1. ユースケース記述からフローを列挙する(基本フロー、代替フロー、例外フロー)。
  2. 各フローを1つのテストケースに写す(基本1 + 代替各1 + 例外各1)。
  3. 各ケースの事前条件(アクター、在庫、権限など)を分岐ごとに具体化する。
- **達成チェック(漏れの検出)**：列挙したフローのうちケース未割当の例外や代替が残っていないか(価値は例外側にある)。各ケースの粒度が単体テストに落ちすぎていないか(フローの完結を見ているか)。

---

## シナリオテスト(Scenario Testing)

### 概要
実利用に即した一連の操作の物語(複数ユースケースをまたぐ現実的な経路)を組み、通しで検証する。

### 目的/いつ使う
個々の機能は通るのに、組み合わせた現実の使い方で破綻しないかを見たいとき(登録 → 解約 → 再登録、長期セッションでの状態蓄積など)。
ユースケーステストより広い文脈、すなわち複数機能の連鎖を対象にする。
単機能の検証には重い。

### TypeScript example
解約後の再登録でデータが正しく引き継がれるか引き継がれないかを、現実的な操作列として1本に綴る。

```ts
import { describe, it, expect } from "vitest";
import { Account } from "./account";

describe("scenario: churn and return", () => {
  it("re-registration starts fresh after cancellation", () => {
    const acc = new Account("bob");
    acc.subscribe("pro");
    acc.cancel();
    acc.subscribe("free"); // 戻ってきた
    expect(acc.plan).toBe("free");
    expect(acc.history).toHaveLength(3); // 履歴は保持
  });
});
```

### 落とし穴
- シナリオが壊れたとき、どのステップが原因か切り分けにくい。要所に中間アサーションを置く。
- 「ありそうな話」を盛り込みすぎて非現実的な経路を検証しがち。実データや実ログを下敷きにする。

### 網羅の定義
シナリオも単独で網羅を主張せず、体系的技法の上に重ねる仕上げである。

- **網羅基準(いつ網羅完了とみなすか)**：想定する現実利用シナリオ集合(実データや実ログ由来)を各1本ずつ通したとき。
- **網羅手順(基準を満たすケース集合の作り方)**：
  1. 複数ユースケースをまたぐ現実の経路を実ログや実利用データから抽出する。
  2. 抽出した各シナリオを1本の通しテストに綴る。
  3. 経路の要所(状態が切り替わる地点)に中間アサーションを置く。
- **達成チェック(漏れの検出)**：各シナリオが実利用に基づくか(実ログに無い空想経路を作っていないか)。テストが壊れたとき原因ステップを切り分けられるか(中間アサートが足りているか)。

---

## 構文テスト(Syntax Testing)

### 概要
入力の文法(BNF や正規表現)を起点に、文法に従う正常入力と、文法を1箇所だけ壊した不正入力を機械的に生成して叩く。
エラー推測(直感で壊す、[`experience-heuristic.md`](experience-heuristic.md))の近縁で、こちらは「壊し方」を文法の構造から系統立てて出す。

### 目的/いつ使う
入力フォーマットが文法で定義できるとき(メールアドレス、日付、URL、設定ファイル、プロトコルメッセージなど)に、パーサやバリデータの受理/拒否が正しいかを確かめる。
不正生成は1つの production(文法規則)を1箇所だけ壊すのが要点で、欠落・余分・順序入替・型違反の4種を当てる。複数同時に壊すと、どの規則で弾けたか切り分けられなくなる。
文法で表せない意味制約(値の整合、業務ルール)はデシジョンテーブルやメタモルフィックへ回す。

### TypeScript example
`YYYY-MM-DD` の日付文法(`digit{4} "-" digit{2} "-" digit{2}`)から、正常列と各 production を1箇所壊した不正列を `it.each` で回す。

```ts
import { describe, it, expect } from "vitest";
import { isIsoDate } from "./date";

describe("isIsoDate: syntax testing (YYYY-MM-DD)", () => {
  const valid = ["2026-06-29", "2000-01-01"] as const;
  it.each(valid)("accepts %s", (s) => {
    expect(isIsoDate(s)).toBe(true);
  });

  // 各不正は1 production を1箇所だけ壊したもの
  const invalid = [
    { input: "2026-6-29", desc: "month digit 欠落" },
    { input: "2026--06-29", desc: "区切り 余分" },
    { input: "06-2026-29", desc: "year/month 順序入替" },
    { input: "20X6-06-29", desc: "digit に型違反(英字)" },
  ] as const;
  it.each(invalid)("rejects $desc", ({ input }) => {
    expect(isIsoDate(input)).toBe(false);
  });
});
```

### 落とし穴
- 1つの不正入力で複数の規則を同時に壊すと、目的の規則で拒否されたのか別の規則で弾かれたのか分からない。1ミューテーション1ケースに保つ。
- 正常方向(文法に従う入力の受理)を出し忘れ、拒否ばかり並べる。受理側を踏まないと「常に false を返すだけ」のバグを見逃す。
- 文法に表れない意味制約(2026-02-30 のような暦上あり得ない日付)を構文テストで網羅しようとする。それは別技法の領分。

### 網羅の定義
- **網羅基準**：文法の全 production を最低1回は正方向(従う入力)で踏み、かつ各 production について1ミューテーション(欠落/余分/順序入替/型違反のいずれか)を踏んだとき網羅完了。
- **網羅手順**：
  1. 入力フォーマットを BNF か正規表現で書き下し、production を列挙する。
  2. 全 production を通る正常入力を最低1本作る。
  3. 各 production を1箇所だけ壊した不正入力を1つずつ作る(壊し方は欠落・余分・順序入替・型違反から選ぶ)。
- **達成チェック**：ミューテーションが割り当たっていない production が0であること、正常入力の受理ケースが1本以上あることを確認する。複数規則を同時に壊した不正ケースが混ざっていないか見る。

---

## 関連 reference

- 経験・乱数を起点にする非形式技法(エラー推測、ランダムファジング、探索的、アドホック)：[`experience-heuristic.md`](experience-heuristic.md)
- 入力空間の分割と履歴(同値分割、境界値、状態遷移)：[`blackbox-partition.md`](blackbox-partition.md) / [`blackbox-state.md`](blackbox-state.md)
- 組合せの縮約・論理ベース(原因結果グラフ、クラシフィケーションツリー)：[`blackbox-cause-effect.md`](blackbox-cause-effect.md)
- 組合せの縮約・因子被覆(ペアワイズ、直交表、T-way)：[`blackbox-covering.md`](blackbox-covering.md)
- 本格的な生成系ファジング・PBT：[`generative-property.md`](generative-property.md) / [`generative-fuzzing.md`](generative-fuzzing.md)
- oracle 代替・過去出力/別実装(ゴールデン、承認、差分)：[`oracle-snapshot.md`](oracle-snapshot.md)
- oracle 代替・関係/モデル(メタモルフィック、モデルベース、形式検証連携)：[`oracle-relational.md`](oracle-relational.md)
