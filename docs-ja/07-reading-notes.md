# 07. 読解メモ — 気づいた点と注意点

コードを読む上での注意点をまとめました。いずれもコードの挙動を変えるものではなく、読み手向けの注意書きです。

直すべき問題として整理したものは [08-improvements.md](./08-improvements.md) にあります。この文章は仕様として知っておけばよいことが中心です。

> [!NOTE]
> 手元の環境に `nix` が無いため、以下はコードの読解に基づく指摘です。実際のビルド・動作までは確認していません。

## 1. 存在しないテーマ名は警告も出ずに無視される

```nix
findThemeByName = themeName: pkgs.hydenix-themes.${themeName} or null;
```

`or null` があるため、タイプミスしてもビルドは成功し、そのテーマだけ入りません。`demo/home.nix` の `"Some Theme"` は、この挙動を検証するためのテスト用エントリです。

テーマが適用されないときは、まず名前のスペルを見直してください。正しい名前は `pkgs/hydenix-themes/default.nix` のキーで確認できます。（`"Rosé Pine"` / `"Mac OS"` / `"Catppuccin-Macchiato"` のように表記が不規則です）。

なお、Hyprland の `animations.preset` などは逆に、存在しない名前を書くと評価時の assertion で止まります。挙動が統一されていない点に注意してください。

## 2. `home.file` が同じファイル内に 2 回出てくる

`modules/hm/rofi.nix` には `home.file = {...};` が 2 回書かれています。

Nix では同じ属性パスに属性集合リテラルを2回代入した場合、自動でマージされるため（`{a = {x=1;}; a = {y=2;};}` → `{a = {x=1;y=2;};}`）、エラーにはなりません。値がリテラルでない場合（`{a = 1; a = 2;}`）はエラーになります。

`treefmt.nix` で statix の `repeated_keys` lint を無効化しているのは、この書き方があるためです。

## 3. 同じパスを複数モジュールが定義している

| パス | 定義しているファイル |
|-----|-------------------|
| `.config/kdeglobals` | `dolphin.nix` / `qt.nix` |
| `.config/menus/applications.menu` | `dolphin.nix` / `qt.nix` |
| `.config/electron-flags.conf` | `hyde.nix` / `social.nix` / `spotify.nix` |

内容が同一なのでマージされ、エラーになりません。ただし片方だけ変更するとその瞬間に定義衝突でビルドが落ちます。どれか1つを編集するときは、他の定義箇所も揃える必要があります。

## 4. `mkHyprConfig` は生成物をすべて mutable にする

本家では `monitors.conf` だけが `mutable = true` で、`keybindings.conf` などはリンクとして配置されています。

フォークでは `mkHyprConfig` が生成する `hypridle.conf` / `hyprlock.conf` / `hyprsunset.conf` がすべてコピーです。HyDE の `hyprlock.sh` がレイアウトを切り替えるときに `hyprlock.conf` を書き換えるため、3 つとも mutable にしています。

|         | 利点 | 欠点 |
|---------|-----|------|
| mutable | HyDE のスクリプトが書き換えられる。手で編集してすぐ試せる | 手で編集した内容は次の rebuild で上書きされる |

## 5. `pyprland` はオプションごと消えている

本家では `pyprland.nix` は存在するが `imports` に無いという状態で、オプションだけあって何も起きない、という分かりにくい挙動です。

フォークには `pyprland.nix` とオプション定義のどちらも無いため、`hydenix.hm.hyprland.pyprland.*` を書くと未定義エラーで止まります。警告も出ずに無視されるよりは親切な挙動です。

## 6. `hyde-diff-upstream` の master は commit で固定されている

```nix
# pkgs/hyde-diff-upstream/default.nix
hyde-master = pkgs.hyde.overrideAttrs (old: {
  src = pkgs.fetchFromGitHub {
    owner = "HyDE-Project";
    repo = "HyDE";
    rev = "fa2fd57afc7203b1b5653d3271f3a57ea3873f97";   # master 上の commit
    sha256 = "sha256-/9oT3c60hZQtVdfbZWWUFo7GeU0pHQOWwhfsFELMoNE=";
  };
  passthru = (old.passthru or {}) // {updateBranch = "master";};
});
```

`rev` には master 上の commit を書き、`passthru.updateBranch = "master"` で追っているブランチを示しています。`update-branch-pins.yml` が毎週日曜にこの commit を master の先頭へ進めるので、比較相手は最大 1 週間遅れの master です。

nix-update は `src` を定義しているファイルを書き換えます。ここでは `overrideAttrs` の中で `src` を定義しているので、書き換わるのはこのファイルで、`pkgs/hyde` の rev はそのままです。

## 7. 名前の紛らわしい重複

| 名前 | 場所 | 中身 |
|-----|------|-----|
| `flake.nix` | ルート | hydenix 本体（**提供する側**） |
| `flake.nix` | `template/` | 利用者の雛形（**利用する側**） |
| `default.nix` | `pkgs/` | overlay の本体 |
| `default.nix` | `modules/hm/`, `modules/system/` | サブモジュールを `imports` でまとめて読み込むファイル |
| `configuration.nix` | `demo/` | 開発者向けリファレンス設定 |
| `configuration.nix` | `template/` | 利用者が編集する設定 |
| `hardware-configuration.nix` | 両方 | どちらもダミー（実機では要置換） |
| `shell.nix` | ルート | devShell（`nix develop` 用） |
| `shell.nix` | `modules/hm/` | zsh/bash/fish の設定モジュール |

`demo/` は hydenix 自身の検証用であり、利用者が触る場所ではありません。

## 8. VM で試すときの注意

```bash
nix run github:santamn/hydenix
```

- 設定を変えたら `rm hydenix.qcow2` でディスクイメージを消してから再実行する: 消さないと古い状態が残る
- KVM が使えない環境ではまともに動きません
- Hyprland が起動しない場合は[virtio ガイド](https://santamn.github.io/hydenix/faq.html#how-do-i-run-hyprland-in-a-vm) を参照
