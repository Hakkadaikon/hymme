---
name: loopeng-smt
description: >
  loop-engineering の SMT 経路。状態を持たない判定(述語・許可/拒否ルール・設定やルール集合・
  形式変換)が「どんな入力でも」成り立つかを Z3 で検査する。性質ごとに期待(HOLDS/VIOLATED)と
  わざと壊した版を書き、smt_oracle.py が判定と「検査が効いているか」を同時に確かめる。
  「この条件どんな入力でも成り立つ?」「設定が矛盾していないか」「死んだルール」「Z3」「SMT」
  「リファクタ前後で同じ意味か」と言われたとき、または loop-engineering ルーターが
  「全入力 × 一瞬」の問いと判定したときに使用する。順序・並行・時間が問いなら TLA+ の経路(loopeng-formalize)。
  前提: loopeng-extract の抽出台帳が閉じていること。
---

# loopeng-smt (全入力 × 一瞬: 判定を Z3 で検査する)

TLA+ は「どの順番で起きても」を総当たりする。状態を持たない判定の問いは「どんな入力でも」で、こちらは SMT ソルバーが一発で答える。
対象がデータ(設定・ルール)なら、モデルが実データをそのまま読めるので、モデルと本番のずれが小さい。

**前提**: `tasks/loopeng/<Name>.extract.md` の台帳が閉じていること(loopeng-extract)。判定ごとに [`../_shared/failure-semantics.md`](../_shared/failure-semantics.md) の問いへ答えてあること。`tasks/verifiability/<Name>.md` の検証容易性の台帳が通っていること([`../verifiability/SKILL.md`](../verifiability/SKILL.md) の「強制のしくみ」)。

## 向くもの / 向かないもの

- 向く: 条件が区間・集合の所属・等式・線形の整数演算・真偽の組み合わせで書ける判定。許可/拒否ルール、ターゲティング、料金や割引の条件、設定の整合性、旧形式と新形式の等価性。
- 向かない: 状態遷移や順序(→ loopeng-formalize)、確率や分布、浮動小数の誤差が本質のもの、非線形で Z3 が `unknown` を返すもの。
- **有限で小さいなら Z3 も要らない**: 入力の直積が数万程度に収まるなら、普通のコードで全列挙するテストが最も安い(ルーターの判断)。

## 手順

1. **判定を純粋関数として書き出す**: 実装の配管(I/O・フレームワーク・DB)を剥がし、観測できる入力 → 結果、の関数をモデルに写す。実装を読みながら写し、記憶や要約から組まない(変換表を1つ取り違えると偽の証明になる)。
2. **性質に名前を付け、期待を先に決める**: 台帳の要件ごとに `claim` を書き、`expect` を決める。
   - `HOLDS`: どの入力でも成り立つはずの契約。成り立てば回帰の歯止めとして残す。
   - `VIOLATED`: 破れる入力があるはずのもの。既知の穴の記録、または「この条件は満たせる」の確認(`claim = Not(cond)` が VIOLATED なら、witness が cond を満たす入力)。
   - 設定の各ルールには「満たせる(死んでいない)」を必ず1本書く。
3. **わざと壊した版を書く**: `HOLDS` の性質には、ガードを外す・否定を落とす・境界を1ずらした `broken` を添える。壊した版が `VIOLATED` にならなければ、その claim は何も縛っていない。
4. **回す**: `smt_oracle.py tasks/loopeng/<Name>.smt.py`。exit 0 で全判定が期待どおり。
5. **期待と違ったら**: witness(破る入力)が出る。それを持って「これは意図か?」を要件側に問う。意図なら要件と期待を直し、意図でなければ設計・実装の穴として loopeng-gherkin と同じく受け入れ仕様(失敗するシナリオ)に固定してから直す。

モデルファイルの形(`properties()` が性質の dict のリストを返す):

```python
from z3 import *

def properties():
    total = Int("total"); weight = Int("weight")
    free = total >= 5000           # 実装の比較をそのまま写す(文書は「5000 円以上で無料」)
    return [
        dict(name="FreeShippingFrom5000", expect="HOLDS",
             claim=Implies(total == 5000, free),
             broken=Implies(total == 5000, total > 5000)),
        dict(name="HeavyRuleCanMatch", expect="VIOLATED",
             claim=Not(And(weight > 30, weight <= 50))),
    ]
```

この2本は緑になる。設定のルールが `weight > 30 かつ weight <= 25` のように満たせなければ、`...CanMatch` の性質に HOLDS が返り、期待 VIOLATED と食い違うので oracle は `<- 期待は VIOLATED` を付けて赤にする。これが、満たせる入力が無い(死んだ設定)という意味になる。

## 出口条件

- `smt_oracle.py` が exit 0(全性質が期待どおり、`HOLDS` は全件で壊した版を捕まえる)。exit 3(Z3 の `unknown`)は証拠にしない。性質を決定可能な形に書き直すか、全列挙・property-based testing へ逃がす。
- 台帳のトレーサビリティ表「形式手法」列に性質名を消し込む。空欄の要件 = この経路の漏れ。
- 出た witness は全件、要件側の判断(意図/穴)が付いている。

## やらないこと

- 壊した版の無い `HOLDS` を「証明済み」と言わない(何も検証していない緑)。
- 決定不能な述語(量化子の入れ子・非線形)を粘らない。Z3 が `unknown` を返したら経路を変える。
- 全部を形式化しない。主要な契約と危険な穴を押さえたら、溜まった witness と確認質問を要件側と捌く方が効く。
- 成果物(`<Name>.smt.py`)は `tasks/loopeng/` 配下・git 管理外([`../_shared/stealth-artifacts.md`](../_shared/stealth-artifacts.md))。回帰の歯止めとして本体に残すなら、性質を通常のテスト(全列挙・property-based)に書き直して置く。

## 次の工程

出口条件を満たしたら loop-engineering ルーターへ戻り、完了前ゲート(コントローラが `hymme:loop-engineering-reviewer` を dispatch)へ進む。受け入れシナリオは test-extract へ渡す。
