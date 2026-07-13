# 実行時の罠

踏むと時間を溶かす。動かないときまずここを疑う。

## TLC/SANY が `NullPointerException`(`tmpDir is null`)で即死

TLC/SANY を叩く JDK は tmp ディレクトリを作れないと即死する。
サンドボックス等で `$HOME` のキャッシュが read-only なときに起きる。
必ず次の上で呼ぶ。

```sh
export TMPDIR="${TMPDIR:-/tmp}"; mkdir -p "$TMPDIR/tla"
_JAVA_OPTIONS="-Djava.io.tmpdir=$TMPDIR/tla"
```

`loop-middle` 等が動かないときはこれを疑う。

## cfg と module の名前ミスマッチで `Cannot find source file for module`

1つの `.tla` を複数の cfg で検査する運用(safety と action property と liveness を別々の cfg に分ける)でよく踏む。
`tlc -config Foo.cfg Foo.tla` を前提にした薄いラッパーに `Foo.cfg` だけ渡すと、ラッパーが `Foo.tla` を探し、それが存在せず即死する。
cfg 名が module 名と一致するとは限らないからである。

cfg は SPECIFICATION や INVARIANT、PROPERTY を指す設定にすぎず、検査対象の `.tla` とは独立している。
正しくは、対象 module の `.tla` と使いたい cfg を別々に渡す。

```sh
# NG: ラッパーが ReliableQueueProp.tla を探して落ちる
run-tlc.sh ReliableQueueProp
# OK: 同じ spec に別 cfg を当てる
java ... tlc2.TLC -config ReliableQueueProp.cfg ReliableQueue.tla
```

ラッパーを書くなら、module 名と cfg 名を別の引数にする。
`-config` を握りつぶして `${MOD}.cfg ${MOD}.tla` 固定にすると、この multi-cfg 運用ができなくなる。

## TLC がスクラッチを撒く

TLC は作業ディレクトリに `states/` などのスクラッチを吐く。
spec ディレクトリに撒かれるので、コミット前に消す/`.gitignore` する。
生成物(`.tla`/`.feature`)と混同しない。

## TLC のトレース形式(`trace_to_gherkin.py` 絡み)

TLC 1.8 系は状態変数を `/\ var = value`(conjunct 形式)で出す。
古い `var = value`(flat 形式)前提のパーサだと**全変数を取りこぼし、空の `Then the state is unchanged` を吐く**。
`trace_to_gherkin.py` の `ASSIGN_RE` は両形式を受ける(`^(?:/\\\s*)?...`)。
検証ツールの selfcheck は**対象 TLC が実際に出す形式**で書くこと。
flat 形式だけで self-check すると、この回帰を素通りさせる。

## `trace_to_gherkin.py` が取りこぼすバグ

`trace_to_gherkin.py` は「**変化した**変数」だけを `Then` に出す。
よって「違反時に**不変であるべき値が変わってしまう**」型のバグ(例: close 時に frag を破棄し忘れ、frag が前状態のまま残る)は、その変数が反例トレース上で前後不変なら `Then` に現れず、生成テストでは捕まらない。
これはトレース→Gherkin の構造的限界。
捕まえたいなら全変数を毎ステップ `Then` に出すか、その不変条件を中ループ(mutation oracle / 別 invariant)側で締める。
