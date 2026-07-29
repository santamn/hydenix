# 03. HyDE を NixOS 向けにパッケージ化する

対象ファイル: [`pkgs/hyde/default.nix`](../pkgs/hyde/default.nix)

## 何が問題なのか

HyDE はもともと **Arch Linux 用**の設定集です。そのまま NixOS に持ってくると、
主に次の 4 つの理由で動きません。

| 問題 | 具体例 |
|---|---|
| プロセス名が違う | NixOS はラッパー経由で起動するので、実プロセス名が `.waybar-wrapped` になる |
| 設定がシンボリックリンク | `find` がリンクをたどらず、設定ファイルを見つけられない |
| バイナリの入手方法が違う | Arch は `pacman` 前提。NixOS では Nix パッケージを使う |
| アーカイブが未展開 | フォント・アイコン・GRUB テーマが `.tar.gz` のまま同梱されている |

`buildPhase` は、これらを 1 つずつ潰していく処理です。

## buildPhase がやっていること

### (1) 不要なファイルの削除

```bash
rm -rf Source/assets                        # 素材フォルダ（実行時に不要・容量が大きい）
rm -rf Configs/.local/lib/hyde/resetxdgportal.sh
rm -rf Configs/.local/bin/hydectl
rm -rf Configs/.local/bin/hyde-ipc
rm -rf Configs/.local/lib/hyde/hyde-config
rm -rf Configs/.local/lib/hyde/hyq
rm -rf Configs/.local/bin/hyq
```

`hydectl` / `hyq` / `hyde-ipc` / `hyde-config` は、HyDE に同梱されているものではなく
**Nix パッケージとして別途ビルドしたバイナリ**を使います（`pkgs/` 以下にそれぞれ定義があります）。
そのため同梱版を削除して、確実に Nix 版が使われるようにしています。

`resetxdgportal.sh` は、あとで [`modules/hm/hyde.nix`](../modules/hm/hyde.nix) が
**空のスクリプトに差し替え**ます。NixOS では XDG ポータルを systemd が管理するので、
HyDE 側の再起動処理は不要（というより邪魔）だからです。

### (2) プロセス名の置換

```bash
find . -type f -print0 | xargs -0 sed -i 's/killall waybar/killall .waybar-wrapped/g'
```

NixOS では、多くのプログラムが「環境変数を設定してから本体を呼ぶ」ラッパースクリプト経由で
起動されます。このとき実プロセス名が `.waybar-wrapped` のように**先頭ドット付き**になります。

HyDE のスクリプトは `killall waybar` でバーを再起動しようとしますが、
NixOS ではその名前のプロセスが存在しないため失敗します。
そこで置換して名前を合わせています。waybar / dunst / kitty の 3 つが対象です。

### (3) find のシンボリックリンク対応

```bash
find . -type f -executable -print0 | xargs -0 sed -i 's/find "/find -L "/g'
find . -type f -name "*.sh" -print0 | xargs -0 sed -i 's/find "/find -L "/g'
```

home-manager は設定ファイルを Nix ストアへのシンボリックリンクとして配置します。
`find` は既定でリンクをたどらないため、HyDE のスクリプトがテーマや壁紙を
見つけられなくなります。`-L` オプションを付けてリンク先を追跡させます。

> [!NOTE]
> 本家は実行ファイルだけを対象にしていましたが、
> このフォークでは `*.sh` も対象に追加されています（2 行目）。

### (4) 個別の不具合対応（フォークでは無効化）

```bash
# remove lines 187-190 from Configs/.local/lib/hyde/theme.switch.sh
# fixes gtk4 themes
# sed -i '187,190d' Configs/.local/lib/hyde/theme.switch.sh

# remove pkill command from rofilaunch.sh
# sed -i '2d' Configs/.local/lib/hyde/rofilaunch.sh
```

本家では**行番号を決め打ちして** `sed` で行を削除していました。
HyDE 本体を更新すると意図しない行を消してしまうため、
このフォークでは**両方ともコメントアウトされています**。

復活させる必要が出た場合は、必ず差分を確認してから行番号を取り直してください。

```bash
nix run .#hyde-diff-upstream    # 固定中の HyDE と上流 master の差分
nix run .#hyde-diff-home        # 固定中の HyDE と自分のホーム構成の差分
```

### (5) アーカイブの展開

```bash
mkdir -p $out/share/fonts/truetype
for fontarchive in ./Source/arcs/Font_*.tar.gz; do ... done
```

フォント・VS Code 拡張・GRUB テーマ・アイコン・GTK テーマを `$out/share/` 以下に展開します。
これにより、他のモジュールから次のように参照できるようになります。

```nix
# modules/system/boot.nix
theme = pkgs.hyde + "/share/grub/themes/Retroboot";

# modules/hm/editors.nix
".vscode/extensions/prasanthrangan.wallbash".source =
  "${pkgs.hyde}/share/vscode/extensions/prasanthrangan.wallbash";
```

### (6) installPhase と postInstall

```bash
mkdir -p $out
cp -r . $out
```

手直し済みのソースツリー**全体**を `$out` にコピーします。
これにより `${pkgs.hyde}/Configs/...` という形で、
HyDE の元のディレクトリ構造をそのまま参照できるようになります。

さらに `postInstall` で `hyde-shell` にラッパーを被せ、
Python 本体と `pyamdgpuinfo` を `PATH` / `PYTHONPATH` に注入しています
（HyDE のスクリプトの一部が Python を呼ぶため）。

## 完成したパッケージの構造

```
/nix/store/xxxx-hyde/
├── Configs/                    ← HyDE の元のディレクトリ構造そのまま
│   ├── .config/hypr/...        ←   各モジュールが source / readFile で参照する
│   ├── .local/lib/hyde/...     ←   スクリプト群
│   └── ...
└── share/                      ← buildPhase で展開したもの
    ├── fonts/truetype/
    ├── vscode/extensions/
    ├── grub/themes/
    ├── icons/
    └── themes/
```

## 参照される流れ

```mermaid
flowchart LR
    A["fetchFromGitHub<br/>(HyDE の生ソース)"]
    B["pkgs/hyde/default.nix<br/>buildPhase で手直し"]
    C["pkgs.hyde<br/>(overlay 経由)"]
    D["modules/hm/hyde.nix<br/>ホームへ配置"]
    E["~/.config/...<br/>~/.local/..."]

    A --> B --> C --> D --> E
```

## HyDE を更新するときの手順

`pkgs/hyde/default.nix` の `rev` と `hash` を書き換えるのが基本ですが、
HyDE はスクリプトの塊なので、更新すると壊れやすい部分があります。

1. `nix run .#hyde-diff-upstream` で上流の変更を確認する
2. `rev` / `hash` を更新する
3. `nix run .#hyde-diff-home` で、自分のホーム構成に配置されないファイルが
   増えていないか確認する（新しい設定ファイルが追加されていたらモジュール側の追従が要る）
4. VM (`nix run .`) で動作確認する

## 覚えておくとよいこと

- **HyDE の設定ファイルの実体は必ず `pkgs.hyde` の中にある。**
  `~/.config/hypr/hyprlock.conf` を見ても、実体は `/nix/store/...` へのリンクです。
- **リンク先を編集しても意味がない**（読み取り専用なので編集できない）。
  設定を変えたいときは Nix 側のオプションを使います → [06](./06-hyprland-modules.md)
- **例外が `mutable` 指定のファイル**。こちらは実体がコピーなので編集できます → [04](./04-mutable-files.md)
