# mutation oracle と equivalent-mutant

中ループの mutation oracle(`tla_mutate_oracle.py`)の運用詳細。
spec に機械的ミューテーション(`<`→`\leq`、`=`→`#`、`/\`→`\/`、`+`→`-`)を注入し、それぞれ TLC が検出(killed)するか確認する。

**survivor が出たら spec が弱い。**
ミューテーションを TLC が捕まえられない = 不変条件や `Next` がそのバグを区別できない。

## killed も信じるな(変異が当たったか先に確認する)

survivor を侮るのと逆向きの罠がある。
`killed` の判定を「TLC がエラーを吐いたか」だけで下すと、変異が一度も当たっていないケースを killed と誤認する。
実地で踏んだ。

regex や perl、sed の置換が一致せず空振りし、変異体が原本と byte 単位で同一になっていた。
それでも別の壊れた版が緑か赤を出すと、verdict 関数が「変異なし(元の spec の結果)」をそのまま killed か survivor に流し、置換ミスを killed と取り違えた。
survivor は怪しんで調べるが、killed は安心して放置する。
だから false-killed の方が気づきにくい。

verdict を出す前に、必ず次を通す。

1. 変異体と原本の diff が空でないことを確認する。空なら変異が未適用で、killed でも survivor でもなく検査が成立していない。
   ```sh
   diff -q "$mutant.tla" "$base.tla" && { echo "MUTATION NOT APPLIED: $name"; exit 1; }
   ```
2. 置換が変えた行数を assert する(perl なら `-i` の戻り値、sed なら前後の `wc -l` 差や grep でのマーカ確認)。
3. それでも不安なら、変異後の該当行を grep して、意図した字面になっているかを目視する。

**「全 mutant killed」を報告する前に、各 mutant が原本と異なることを示す。**
diff の確認を伴わない killed は無効である。

## equivalent-mutant を見分ける(知らないと永遠に終わらない)

regex ベースの oracle は意味を理解せず字面を変異させるので、survivor の多くは「設計の穴」ではなく **equivalent-mutant**(変異しても振る舞いが変わらない=原理的に kill 不能)である。
実例として 100 個超の survivor の大半がこれだったことがある。
次は equivalent と判定してよい(理由を必ず1行残す)。

- **コメント/散文への変異**(`->` や `+` が文中に当たる)。
- **到達状態を縮小するガード変異**(`=`→`#` で spec が凍結し安全性が自明に保たれる)。到達状態グラフが小さくなるだけ。
- **冪等な再発火**(既に立っているフラグをもう一度立てる等、観測不能)。
- **vacuous な property への変異**(現設計で一度も励起されないトレース述語。例: data→data 遷移が無いのに interleave ガードを変異)。
- **構造的 conjunct の `/\`→`\/`**(TypeOK/Init を緩めても到達状態が元々その条件を満たす)。

## 判定の機械的手順

survivor ごとに変異版で TLC を回し、**到達状態グラフ(distinct states 数と遷移)が元と変わるか**を見る。
変わらなければ equivalent。
変わるのに緑なら**真の survivor=設計の穴**で、不変条件を締める。

## 打ち切り基準

「全 mutant kill(survivor 0)」を機械的に要求しない。
AST 非対応の regex oracle では原理的に 0 にできない。
基準は **「真の安全性 survivor が 0」**。
残った survivor が全て上記 equivalent クラスか、源泉が明示的に Lean/test へ委譲した性質(決定性・全域性など)であることを1つずつ確認し、その分類を報告に残す。
そこで打ち切ってよい。

- 状態空間が有限化できない/大きいときは Apalache(`apalache-mc check`)で型チェック+記号検査。
- 発散するミューテーント(無限状態)は `MUT_TIMEOUT=<秒>` で打ち切る(timeout=killed 扱い)。

## survivor を侮らない(実地)

異常系で内部状態を破棄し忘れる(リセット漏れ)バグが survivor として残ったことがある。
「状態 A が NONE ⟺ 累積量が 0」のような双条件の不変条件を置いていても、これだけでは捕まらなかった。
両辺が false のまま vacuous に成立してしまい、「整合したまま残留する」異常状態を区別できないからである。
異常系で必ず両方をリセットする不変条件を別に足して締めた。
これが無ければ実装で外していた箇所だった。
**「mutation が炙り出した穴は実装で外しやすい箇所」**と捉え、TDD のテストリストに最優先で落とす。
双条件の不変条件は両辺 false で空成立しうるので、それだけに頼らない。
