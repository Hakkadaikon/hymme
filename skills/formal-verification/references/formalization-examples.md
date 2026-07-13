# 形式化の例(雑仕様 → def + theorem)

SKILL.md §2(Lean に形式化)のコード例。雑な自然言語仕様が Lean の `def` + `theorem` にどう対応するかを示す。

## 数学的性質: 「ソートは要素を保存し、順序付ける」

```lean
-- 「ソートは要素を保存し、順序付ける」
theorem sort_perm (l : List Int) : (sort l).Perm l := by sorry
theorem sort_sorted (l : List Int) : (sort l).Sorted (· ≤ ·) := by sorry
```

## 状態機械の不変条件: 「状態は逆行しない」「error なら必ず closed」を step の単一ステップ性質に

```lean
-- 状態は逆行しない(単調)。rank で順序を与えて示す。
theorem step_monotone (s : State) (i : Input) : s.rank ≤ (step s i).1.rank := by sorry
-- error を返すなら必ず closed へ(Fail the Connection の一方向性)。
theorem error_implies_closed (s : State) (i : Input)
    (h : (step s i).2 = .error) : (step s i).1 = .closed := by sorry
```

## temporal 性質: 「どう分割受信しても結果は同じ」を trace 述語に

```lean
-- 受信粒度非依存: どう分割しても再構成結果は同じ。
theorem chunking_invariant (c1 c2 : List (List Byte)) (h : c1.flatten = c2.flatten) :
    reassemble c1 = reassemble c2 := by sorry
```
