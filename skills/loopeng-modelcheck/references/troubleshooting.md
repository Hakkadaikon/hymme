# 実行時に起きやすい失敗

起きると時間を失う。動かないときまずここを疑う。

## TLC/SANY が `NullPointerException`(`tmpDir is null`)ですぐ異常終了する

TLC/SANY を実行する JDK は tmp ディレクトリを作れないとすぐ異常終了する。
サンドボックス等で `$HOME` のキャッシュが read-only なときに起きる。
必ず次を設定してから呼ぶ。

```sh
export TMPDIR="${TMPDIR:-/tmp}"; mkdir -p "$TMPDIR/tla"
_JAVA_OPTIONS="-Djava.io.tmpdir=$TMPDIR/tla"
```

`loop-middle` 等が動かないときはこれを疑う。

## cfg と module の名前の不一致で `Cannot find source file for module`

1つの `.tla` を複数の cfg で検査する運用(safety と action property と liveness を別々の cfg に分ける)でよく起きる。
`tlc -config Foo.cfg Foo.tla` を前提にした単純なラッパーに `Foo.cfg` だけ渡すと、ラッパーが `Foo.tla` を探し、それが存在せずすぐ異常終了する。
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
`-config` を無視して `${MOD}.cfg ${MOD}.tla` 固定にすると、この multi-cfg 運用ができなくなる。

## TLC がスクラッチを残す

TLC は `states/` などのスクラッチを spec のディレクトリに出力する。
コミット前に消すか、`.gitignore` に入れる。
生成物(`.tla`/`.feature`)と混同しない。

## TLC のトレース形式(`trace_to_gherkin.py` 絡み)

TLC 1.8 系は状態変数を `/\ var = value`(conjunct 形式)で出す。
古い `var = value`(flat 形式)前提のパーサだと**全変数を読み取れず、空の `Then the state is unchanged` を出力する**。
`trace_to_gherkin.py` の `ASSIGN_RE` は両形式を受け付ける(`^(?:/\\\s*)?...`)。
検証ツールの selfcheck は**対象 TLC が実際に出す形式**で書くこと。
flat 形式だけで self-check すると、この回帰を検出できない。

## `trace_to_gherkin.py` の生成テストで検出できないバグ

`trace_to_gherkin.py` は「**変化した**変数」だけを `Then` に出す。
よって「違反時に**不変であるべき値が変わってしまう**」型のバグ(例: close 時に frag を破棄し忘れ、frag が前状態のまま残る)は、その変数が反例トレース上で前後不変なら `Then` に現れず、生成テストでは検出できない。
これはトレース→Gherkin の構造的限界。
検出したいなら全変数を毎ステップ `Then` に出すか、その不変条件を中ループ(mutation oracle / 別 invariant)側で検査する。
