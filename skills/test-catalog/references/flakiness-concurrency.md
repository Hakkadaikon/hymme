# テストの flaky(協調の非決定性)の体系的対策

同じコードに対して同じテストが、走らせるたびに緑になったり赤になったりする状態を flaky と呼ぶ。
flaky テストは「赤を信用できない」状態を生み、本物の退行をノイズに埋もれさせ、緑を retry で握り潰す悪習を招く。
原因はほぼ常に**テストが制御していない非決定性**にある。

このファイルは flaky のうち、**処理どうしの協調(タイミング・順序)が定まらない**要因(並行・競合、テスト間順序・状態漏れ)を扱う。
末尾に、他の要因とも共通する**総論**(隔離 quarantine、retry 緑詐称の戒め、検出の3軸)を置く。
**外部サービスとの通信・実時間待ち**の要因(外部ネットワーク、タイマー・sleep)は [`flakiness-external.md`](flakiness-external.md)、**値そのものが実行ごとに変わる**要因(時刻、乱数・UUID、浮動小数)は [`flakiness-value.md`](flakiness-value.md) を参照。

各要因は **原因 / 検出法 / 封じ込め / TypeScript example(悪い例→直した例) / 完了チェック** で示す。
検出は「たまたま緑」を破るために**意図的に揺らぎを増幅して再現させる**(再現コマンドと反復回数を必ず添える)。
封じ込めは揺らぎの源をテストの制御下へ引き込む(直列化する、待ち合わせる、ダブルへ置き換える)。
**完了チェック**は「封じ込め完了」と言える機械的判定で、何回連続緑なら閉じるかと、取りこぼしの逆引きを定める。

相互参照:

- 後始末漏れによるテスト間の状態汚染の構成パターンは [`test-structure-lifecycle.md`](test-structure-lifecycle.md) の Four-Phase Test(teardown)を参照。
- 並行・状態遷移・順序の設計そのものをテスト前に固めるなら `loop-engineering`(TLA+)でモデル検査し、反例を回帰テストへ落とす。
- 外部ネットワーク・タイマー sleep は [`flakiness-external.md`](flakiness-external.md)、値の非決定性(時刻・乱数・浮動小数)は [`flakiness-value.md`](flakiness-value.md)。

## 目次

- [並行・競合](#並行・競合)
- [テスト間順序・状態漏れ](#テスト間順序・状態漏れ)
- [共通方針(隔離・検出の総論)](#共通方針隔離・検出の総論)

---

## 並行・競合

### 原因

複数の非同期処理が共有状態へ同時に触れる、または完了順序が保証されない。
スケジューリングのわずかな差で書き込みが前後し、ある実行でだけ古い値を読む・二重に書く。負荷が高い CI でだけ再現するのが厄介な特徴だ。

### 検出法

並列度と負荷を上げて反復し、レース窓を広げる。

1. **同じ操作を多重に同時発行する**:`Promise.all(Array.from({ length: N }, () => op()))` で N を 100→1000 と上げ、取りこぼし(期待値との差)を見る。
2. **反復してレースを引く**:`vitest run path/to.test.ts --repeat=100` で同一テストを多数回回す。1回の緑では競合は見えない。
3. **負荷を掛けて窓を広げる**:CI の並列ワーカー数を上げる(`vitest --pool=threads --poolOptions.threads.maxThreads=N`)、マシンに別負荷を掛けた状態で回す。
4. **再現コマンド**:`vitest run path/to.test.ts --repeat=200 --no-isolate` で1つでも赤が出れば競合が残っている。
5. **設計の網羅は別手段**:テストは有限回の interleaving しか踏めない。全 interleaving の安全性・活性は `loop-engineering`(TLA+)のモデル検査で網羅する。

### 封じ込め

共有状態への到達を直列化するか、順序を明示的に待ち合わせる。

1. **競合区間を1つに絞る**:排他(ロック、キュー、原子的操作)で read→write を不可分にする。
2. **完了を確定させてから次へ**:`await` で前段の完了を待ってから次の操作へ進み、順序を明示する。
3. **設計の正しさはモデル検査で根治**:並行・状態遷移・順序の設計は `loop-engineering`(TLA+)で安全性・活性を検査し、反例トレースを回帰テストへ落とす。テストはその反例の再現に使う。

### TypeScript example

悪い例(read→write が原子的でなく、同時実行で更新が消える):

```ts
// counter.ts
let value = 0;
export async function increment() {
  const cur = value;           // 読む
  await Promise.resolve();      // ここで他の実行が割り込む
  value = cur + 1;              // 書く(古い値に基づく)
}
export const read = () => value;
```

直した例(直列化して原子性を回復し、並列発行で検証する):

```ts
// counter.ts
let value = 0;
let chain: Promise<void> = Promise.resolve();
export function increment() {
  chain = chain.then(() => { value += 1; }); // 直列化
  return chain;
}
export const read = () => value;

// counter.test.ts
import { describe, it, expect } from "vitest";
import { increment, read } from "./counter";

describe("increment: 並列度を上げても取りこぼさない", () => {
  it("100 並列でも 100 になる", async () => {
    await Promise.all(Array.from({ length: 100 }, () => increment()));
    expect(read()).toBe(100);
  });
});
```

### 完了チェック(もれ確認)

- **競合区間が直列化されているか**:共有状態への read→write が、ロック/キュー/原子的操作/`await` 連鎖のいずれかで不可分になっているか。裸の read→`await`→write が残れば未封じ込め。
- **並列度を上げて全緑か**:`vitest run path/to.test.ts --repeat=200 --no-isolate` を高並列ワーカーで回して全緑。並列発行のテストは N=1000 でも期待値ちょうどか。
- **設計をモデル検査したか**:状態遷移・順序を含むなら `loop-engineering`(TLA+)で安全性・活性を検査し、反例が回帰テストに落ちているか(テストだけで全 interleaving は踏めない)。
- **封じ込め完了の判定**:`--repeat=200` 高並列が連続全緑、N=1000 並列発行が取りこぼし無し、設計のモデル検査で反例が尽きたとき封じ込め完了とみなす。

---

## テスト間順序・状態漏れ

### 原因

あるテストが残したグローバル状態(モジュール変数、DB レコード、環境変数、一時ファイル、モックの設定)を次のテストが踏む。
テストが特定の実行順序に暗黙依存し、単独では緑だが順番が変わると落ちる。並列実行や `.only` での絞り込みで初めて露呈する。

### 検出法

順序をシャッフルし、単独実行と全体実行を突き合わせる。

1. **順序をランダム化して反復する**:vitest の `--sequence.shuffle` を有効にし、seed を変えて複数回回す。`for s in (seq 1 30); vitest run --sequence.shuffle --sequence.seed=$s; or echo "RED seed=$s"; end`(fish)。
2. **単独 vs 全体の食い違いを見る**:1テストだけ単独実行(`vitest run -t "テスト名"`)で緑なのに全体実行で赤、またはその逆なら状態漏れ。
3. **隔離を外して炙り出す**:`vitest run --no-isolate` でモジュール状態の共有を強制し、漏れを露呈させる。
4. **再現コマンド**:`vitest run --sequence.shuffle --sequence.seed=<seed>` で特定 seed の赤を確定再現する。

### 封じ込め

共有状態を持たない、または各テストで必ず初期化・後始末する。

1. **毎回まっさらに作り直す**:`beforeEach` で初期状態を構築する。
2. **確保したものを必ず解放する**:`afterEach`(teardown)で DB レコード・一時ファイル・環境変数・モック設定を解放/復元する([`test-structure-lifecycle.md`](test-structure-lifecycle.md) の Four-Phase Test)。`vi.restoreAllMocks()` / `vi.unstubAllEnvs()` を漏らさない。
3. **共有そのものをやめる**:グローバル可変状態・モジュールキャッシュは注入で渡し、テスト間共有を断つ。

### TypeScript example

悪い例(モジュールレベルの状態がテスト間で漏れ、順序に依存する):

```ts
import { describe, it, expect } from "vitest";

const users: string[] = []; // テスト間で共有される

describe("users(状態漏れ)", () => {
  it("追加できる", () => {
    users.push("alice");
    expect(users).toHaveLength(1); // 単独なら緑
  });
  it("空のはず", () => {
    expect(users).toHaveLength(0); // 前のテスト次第で落ちる
  });
});
```

直した例(各テストで状態を作り直し、漏れを断つ):

```ts
import { describe, it, expect, beforeEach } from "vitest";

describe("users(各テストで初期化)", () => {
  let users: string[];
  beforeEach(() => {
    users = []; // 毎回まっさらから始める
  });

  it("追加できる", () => {
    users.push("alice");
    expect(users).toHaveLength(1);
  });
  it("空から始まる", () => {
    expect(users).toHaveLength(0);
  });
});
```

### 完了チェック(もれ確認)

- **確保したものに解放が対応するか**:`beforeEach`/`beforeAll` で作ったもの(レコード・ファイル・スタブ・env)に、`afterEach`/`afterAll` の解放が1対1で対応しているか。`vi.restoreAllMocks` / `vi.unstubAllEnvs` の呼び忘れが無いか grep で確認する。
- **モジュール共有状態が残っていないか**:`grep -rnE '^(const|let|var) .*=' src/**/*.ts` でモジュールレベルの可変状態を洗い、テストが踏むものが注入か初期化で隔離されているか逆引きする。
- **シャッフルで全緑か**:`for s in (seq 1 30); vitest run --sequence.shuffle --sequence.seed=$s; or echo RED; end` が 30 seed すべて緑。
- **単独=全体か**:代表テストを単独実行と全体実行で比べ、結果が一致するか。
- **封じ込め完了の判定**:シャッフル 30 seed が連続全緑、`--no-isolate` でも緑、単独/全体の結果が一致したとき封じ込め完了とみなす。

---

## 共通方針(隔離・検出の総論)

ここは値の非決定性([`flakiness-value.md`](flakiness-value.md))と協調の非決定性の両方に共通する総論である。

### 見つけた flaky は隔離して原因を特定する

flaky を見つけたら、まず**隔離(quarantine)**して原因を特定する。本流の緑を汚さないよう一時的に分離はしてよいが、それは**原因究明までの猶予**であって、放置の口実にしない。
やってはいけないのは、retry(自動再実行)で落ちを握り潰して緑に見せる**緑詐称**だ。retry は非決定性を隠すだけで根治しないどころか、本物の退行まで覆い隠す。原因を各要因に突き止め、検出法で再現させ、封じ込めで断つところまでを1サイクルにする。

### 検出の総論(3軸)

flaky は1回の緑では見えない。揺らぎを意図的に増幅して再現させるのが検出の要諦で、軸は3つある。各軸は反復回数を伴って初めて意味を持つ。

- **seed を変えて反復する**:乱数・property-based・メタモルフィック・浮動小数は seed を振って多数回回す(数百 seed)。特定 seed の最小反例を回帰へ固定する。→ [`flakiness-value.md`](flakiness-value.md)
- **順序をシャッフルして実行する**:`vitest --sequence.shuffle` でテスト実行順をランダム化し、状態漏れ・順序依存を露呈させる。単独実行と全体実行の食い違いを見る。
- **並列度を上げる**:同時実行数・マシン負荷を上げてレース窓を広げ、競合・実時間 sleep を炙り出す(`--repeat` × 高並列)。

### 封じ込めの総論

封じ込めの共通の型は、**非決定性の源をテストの制御下へ引き込む**ことに尽きる。
時刻・乱数は注入して固定し([`flakiness-value.md`](flakiness-value.md))、外部依存はダブルへ置き換え、実時間待ちはフェイクタイマーか条件待ちにし、共有状態は初期化・後始末で断つ。
テストが結果を**決められる**状態にできたとき、flaky は消える。

### 封じ込め完了の総論的判定

各要因の「完了チェック」を満たしたうえで、スイート全体で次が連続して緑になったとき、flaky の封じ込めが完了したとみなす。

1. `vitest run --sequence.shuffle --repeat=N`(N は数十)を高並列・seed を振って回し、全緑。
2. ネット遮断・負荷(CPU 制限)下でも全緑。
3. 検出法で再現していた赤が、再現コマンドで二度と出ない。

1回の緑では判定しない。連続緑の本数で機械的に閉じる。
