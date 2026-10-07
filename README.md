# Titan Slim: Ubuntu Touch 20.04 で Lomiri が起動しない問題の修正

Fix for Lomiri not starting on the Unihertz Titan Slim with the official Ubuntu Touch 20.04 (focal) image.

Unihertz Titan Slim (MT6771 / Helio P60 / Mali-G72) に、公式の Ubuntu Touch 20.04 (focal) を入れても画面が出ない。これを直す。

ベースは公式の [`unihertz-titanslim-pocket`](https://github.com/ubuntu-touch-unihertz-titan/unihertz-titanslim-pocket)。公式が正式にサポートしているのは 16.04 (xenial) で、20.04 は開発中の扱い。この修正は 20.04 専用だ。
## なにこれ？
Titan Slimでubuntu touchを使いたかったんだが、元のリポジトリとか参考にしてやってみてもまともに動かないから気合でイメージ焼き直したやつ。
音声ドライバとかキーボードのドライバは一切書いてないからそこら辺はまともに動かない。


## 何でまともに起動しなかったのか 

- 起動時に Lomiri (画面を担当するやつ) が、Mali (GPU) に「お前の名前は?」と聞く。
- 聞くタイミングが悪くて Mali が「知らん」と NULL を返し、Lomiri がコケる。
- 「知らん」のときだけ適当な名前を返す小さなライブラリ (shim) を挟んで直した。もう1つ、起動引数の `--vt` も除いている。

## ここに出てくる用語

| 用語 | ざっくりいうと |
|---|---|
| Ubuntu Touch (UT) | スマホ向けの Ubuntu。UBports が作っている |
| Lomiri | UT の画面 (ホーム画面やランチャー) を出すシェル |
| Mir | Lomiri の下で動く表示サーバー。画面に絵を出す係 |
| LSC (lomiri-system-compositor) | Mir を使って実際に画面を握るプロセス。`lightdm` が起動する |
| Halium | Android のドライバー (HAL) を借りて、Linux を動かすための土台 |
| libhybris | Android 用ライブラリ (Bionic libc 向け) を、普通の Linux (glibc) から呼べるようにする橋渡し |
| Mali | この端末の GPU。ドライバーは Android 用のバイナリ (ブロブ) で、ソースは無い |
| EGL / GLES | GPU に絵を描かせる API。EGL が「描く場所」を用意し、GLES が描く |
| コンテキスト | GL が「いま誰の絵を描いているか」を覚えておく状態。スレッドごとに1つ current にできる |
| `LD_PRELOAD` | プロセス起動時に、指定した共有ライブラリを先に読ませる仕組み。関数を差し替えられる |
| shim | 間に挟んで挙動を少し変える薄いライブラリ |

## 症状

- `lightdm` は active なのに、Lomiri のセッションが始まらない。
- `/var/log/lightdm/unity-system-compositor.log` に `Exception while creating graphics platform` が延々と出る。
- `lomiri-system-compositor` を手で動かすと、`GL_VENDOR = ` の直後に `free(): invalid pointer` で落ちる。

この `free(): invalid pointer` が曲者で、GPU ドライバーとメモリ確保の不整合に見えたんだがなんか違った。

## 原因

起動の流れ。

```
lightdm → lsc-wrapper (シェルスクリプト) → lomiri-system-compositor (Mir)
                                              └→ libhybris → Android の Mali ブロブ
```

原因は2つ。

### 1. `glGetString` が NULL を返す

1. Mir の android2 プラットフォームは、初期化の途中で `eglMakeCurrent(dpy, 0, 0, 0)` を呼ぶ。これでコンテキストを外す。
2. そのあと LSC の初期化コールバックが `glGetString(GL_VENDOR)` を呼ぶ。
3. コンテキストが無い状態でこの Mali を呼ぶと、NULL が返ってくる。
4. LSC は NULL を確認せず `std::cerr << vendor` に渡す。NULL を流すと出力が止まる。ログが `GL_VENDOR = ` で途切れるのはこのため。
5. そのあと blacklist チェックで例外が飛び、LSC は終了する。
6. 終了処理で `HWCMediator` (MediaTek の hwcomposer) のデストラクタが走り、そこで `free()` が abort する。

大体他の GPU のブロブは、コンテキストが無くても `glGetString` が文字列を返すらしい。そのため LSC のこの書き方が、他の端末では問題にならない。

### 2. lightdm が `--vt 1` を渡す

`lsc-wrapper` は `--console-provider=none` で LSC を起動する。ここに lightdm が `--vt 1` を足すと、Mir が `Exception while creating graphics platform` を投げる。ログの例外はこれ。

1 だけ直しても、lightdm 経由ではこっちで落ちる。どっちも直せばいけた。

## 修正内容

| 内容 | ファイル |
|---|---|
| `glGetString` が NULL のときだけ代替の文字列を返す `LD_PRELOAD` shim | `glshim/glshim.c` → `/usr/lib/aarch64-linux-gnu/libglshim.so` |
| `lsc-wrapper` に shim を足し、`--vt N` を取り除く | `patches/lsc-wrapper.patch` |

shim は元の `glGetString` を呼んで、結果が NULL のときだけ `ARM` / `Mali-G72` / `OpenGL ES 3.2` を返すようにした。
コンテキストがあるときは元の結果をそのまま返す。

## 使い方

### 読まなくてもClaudeとかCodexにこのリポジトリ投げたら勝手にやってくれると思う。


用意するもの: Titan Slim 本体、公式の `TitanSlim-boot.img` と `TitanSlim-ubuntu.img.xz` (または Releases の修正済みイメージ)。
フラッシュの手順は公式の README に従う。

### A. 修正済みイメージを使う (一番簡単)

Releases の `TitanSlim-ubuntu-lomirifix.img.xz` は、公式の `TitanSlim-ubuntu.img.xz` にこのリポジトリの変更だけを当てたもの。
公式手順の `ubuntu.img` の代わりに置く。

```bash
xz -d TitanSlim-ubuntu-lomirifix.img.xz     # できた ubuntu.img を /data に置く
```

`boot.img` は公式の `TitanSlim-boot.img` をそのまま使う。こちらは変更していない。

### B. 自分でイメージにパッチを当てる

公式の `TitanSlim-ubuntu.img.xz` を用意して実行する。必要なのは `clang`、`lld`、`e2fsprogs` (`debugfs`、`e2fsck`)、`xz`、`patch`。root は要らない。イメージを mount せず、`debugfs` でファイルを直接書き込む。

```bash
tools/patch-image.sh TitanSlim-ubuntu.img.xz out/TitanSlim-ubuntu-lomirifix.img.xz
```

`xz -9` で圧縮するので、20分ほどかかる。

### C. 動いている端末に直接入れる

端末に SSH で入って作業する。多分普通に配られてるイメージだとSSH入ってないと思うからその時はTelnet使えば多分行ける。
イメージは通常 read-only でマウントされているので、先に書き込み可能にする。

起動時に実際に使われるのは `halium-overlay` 側のコピー。両方に適用する。

```bash
make -C glshim                                 # ホストで libglshim.so を作る
# 端末で:
sudo mount -o remount,rw /
sudo install -m 755 libglshim.so /usr/lib/aarch64-linux-gnu/
sudo cp /usr/share/halium-overlay/usr/share/ubuntu-touch-session/lsc-wrapper{,.orig}
cd / && sudo patch -p1 < /path/to/patches/lsc-wrapper.patch      # halium-overlay 側
sudo cp /usr/share/halium-overlay/usr/share/ubuntu-touch-session/lsc-wrapper /usr/share/ubuntu-touch-session/lsc-wrapper
```

戻すときは `.orig` を元の場所に戻す。

## 動作確認

- 実機 (Titan Slim、ストックカーネル 4.14.186 の boot.img) で確認した。bind mount で同じ変更を入れた状態で、画面が点灯し、`lomiri --mode=full-greeter` が起動する。
- 普通にターミナルとかストアは使えた。
- 音声は出ない。wi-fiは行けた。simは知らん。キーボードは数字とかは打てない。
- 公式 README にある既知の不具合 (指紋センサー、カメラ動画撮影) は直していない。

## 個人的炊き散らかしシーン

画面が出ない以前に、起動直後は端末に入る手段がほぼ無い。

- カーネル (boot.img) だけ先に動いた段階では、ログインできるのは Halium の initramfs (起動の最初に動く小さな環境) のデバッグ用 telnet くらいだった。USB 経由 (RNDIS) で繋ぐ。
- 途中で SSH を使える設定をイメージに含めて、焼きなおしたらSSHで接続できるようになった

## 注意

- 対象は 20.04 (focal) のみ。16.04 は別の `usc-wrapper` を使うので関係ない。
- 24.04 への移行は試していない。
- 変更は、UBports 由来の `lsc-wrapper` への差分と、新規の `glshim.c` だけだ。それ以外は公式イメージのまま。
- イメージ内の `rootfs` はアップデートで置き換わる。OTA を当てたら、この修正は消える。

## ライセンス

`glshim/` とスクリプトは MIT (`LICENSE`)。`patches/` は UBports の `lsc-wrapper` への差分で、元ファイルのライセンスに従う。Releases のイメージに入っている各ソフトウェアも、それぞれのライセンスに従う。
