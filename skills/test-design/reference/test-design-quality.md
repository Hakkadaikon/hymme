# 脆さを避けるテスト設計

良いテストの規範のうち、脆さを避けてテストを設計する側面をまとめる。
出典は [`good-test-principles.md`](good-test-principles.md) と同じく Vladimir Khorikov『単体テストの考え方/使い方』。

[`good-test-principles.md`](good-test-principles.md) が「何を検証するか」の基本規範(観察可能な振る舞い・検証スタイル)を扱うのに対し、こちらは同系譜の「どうテストを脆くしないか」を扱う。
脆さの原因を断つ2側面(脆さの回避、モック濫用の回避)を置く。
テストしやすい形へ設計を割る側面(Humble Object、四象限、契約による境界)は [`test-target-design.md`](test-target-design.md) を参照。

各項目は「概要」「目的/いつ使う」「TypeScript example(vitest 想定)」「落とし穴」の構成で示す。
依存の種別ごとにモック可否を引き分ける詳細(ダミー/スタブ/モック/スパイ/フェイク)は [`test-doubles.md`](test-doubles.md) を参照。ここは配置原則、向こうは役割整理を扱う。

## 目次

- [テストの脆さの回避](#テストの脆さの回避)
- [モック濫用の回避](#モック濫用の回避)

---

## テストの脆さの回避

### 概要
振る舞いは正しいのに、内部実装を変えただけで失敗するテストを脆い(fragile)テストと呼ぶ。
脆さの正体は、テストが実装詳細へ結合していることである。

### 目的/いつ使う
リファクタリングのたびに無関係なテストが赤くなる状況を避けたいときに点検する。
脆いテストは偽の警報を出し、やがて開発者がテストの赤を信用しなくなる。
治療は、検証対象を実装詳細から観察可能な振る舞いへ移すことだ。

### TypeScript example
```ts
import { describe, it, expect, vi } from "vitest";
import { Report } from "./report";

// 脆い: 内部でどのヘルパーを何回呼んだかという手順に結合している
it("fragile: asserts internal call sequence", () => {
  const fmt = vi.fn((x: number) => `$${x}`);
  const report = new Report(fmt);
  report.render([1, 2]);
  expect(fmt).toHaveBeenCalledTimes(2); // 内部実装を変えると壊れる
});

// 頑健: 最終出力という観察可能な結果だけを検証する
it("robust: asserts the observable output", () => {
  const report = new Report((x) => `$${x}`);
  expect(report.render([1, 2])).toBe("$1, $2");
});
```

### 落とし穴
- 呼び出し回数や呼び出し順序の検証は、プロセス内協力者に対しては脆さの典型である。
- セットアップを共有しすぎて、一つの変更が広範囲のテストを巻き込み赤くする。

### 網羅設計での効かせ方
脆い網羅とは、実装詳細に結合したまま積み上げた網羅のことだ。
網羅率は高く見えても、リファクタリングのたびに広範囲が赤くなり作り直しを強いる。
これを避けるには、網羅対象を実装詳細から観察可能な振る舞いへ移す。
呼び出し回数や呼び出し順序を網羅対象に含めると、偽警報を量産する網羅になる。
偽警報が続くと開発者は赤を信用しなくなり、網羅そのものが価値を失う。
網羅の達成は最終出力の検証で測り、内部手順の踏破では測らない。
脆い網羅を1つ作るより、頑健な網羅を1つ取る方が長期の退行保護に効く。

---

## モック濫用の回避

### 概要
Khorikov の核心的な主張。
モックは**管理下にないプロセス外依存**(unmanaged out-of-process dependencies)へ向かう通信を検証するときにだけ使う。
プロセス内の協力オブジェクトや、管理下にあるプロセス外依存(自前のデータベースなど)には使わない。

### 目的/いつ使う
何をモックにすべきかを切り分けるときに使う、最重要の指針である。
依存は次のように分かれる。

- **管理下にないプロセス外依存**：他システムから観測される副作用。メール送信、外部 API への呼び出し、メッセージバスへの発行など。これらへの通信はアプリケーションの観察可能な振る舞いの一部なので、モックで検証してよい。
- **管理下にあるプロセス外依存**：自分だけが使うデータベースなど。これは実物(または Testcontainers の本物)を使い、最終状態で検証する。モックにすると実装詳細に結合する。
- **プロセス内の協力オブジェクト**：同じプロセス内のクラス。モックにすると内部構造へ結合し、脆くなる。本物を使う。

### TypeScript example
```ts
import { describe, it, expect, vi } from "vitest";
import { Signup } from "./signup";

// 良い: メール送信(管理下にないプロセス外依存)への通信をモックで検証する
it("sends a welcome email on signup", () => {
  const emailGateway = { send: vi.fn() };
  const repo = new InMemoryUserRepo(); // 管理下の依存はフェイクで実物相当に
  const signup = new Signup(repo, emailGateway);

  signup.register("a@example.com");

  expect(emailGateway.send).toHaveBeenCalledWith("a@example.com");
  expect(repo.findByEmail("a@example.com")).toBeDefined(); // DB は状態で検証
});
```

### 落とし穴
- リポジトリ(管理下の DB)への保存呼び出しをモックで検証し、実装詳細に結合する。状態で確かめる。
- プロセス内のドメインオブジェクトをモック化し、協調手順をテストへ固定してしまう。

### 網羅設計での効かせ方
網羅対象の境界を、依存の種別ごとに引き分けるのがこの規範の使いどころだ。
管理下にないプロセス外依存(メール送信、外部 API、メッセージバス)への通信は、モックで網羅する。
管理下にあるプロセス外依存(自前 DB)は、実物を使い最終状態で網羅する。
プロセス内の協力オブジェクトは、本物を使い振る舞いの結果で網羅する。
この境界を誤り、管理下 DB やプロセス内協力者をモックで網羅すると脆い網羅になる。
依存ごとに「モックで網羅する/状態で網羅する/本物で網羅する」を仕分けてから着手する。
仕分けの達成チェックは、モック検証がプロセス外依存だけに限られているかで行う。

---

テストしやすい形へ設計を割る側面(Humble Object、四象限、契約による境界)は [`test-target-design.md`](test-target-design.md) を参照。
単体テストの基本規範(学派、観察可能な振る舞い、4本柱、検証スタイル)は [`good-test-principles.md`](good-test-principles.md) を参照。
