# 07. 読解メモ — 気づいた点と落とし穴

コードを読んでいて「これは知らないと混乱する」と感じた箇所をまとめます。
いずれも**コードの挙動を変えるものではなく、読み手向けの注意書き**です。

「直すべき問題」として整理したものは [08-improvements.md](./08-improvements.md) にあります。
こちらは「仕様として知っておけばよいこと」が中心です。

> [!NOTE]
> 手元の環境に `nix` が無いため、以下はコードの読解に基づく指摘です。
> 実際のビルド・動作までは確認していません。

## 1. 存在しないテーマ名は黙って無視される

```nix
findThemeByName = themeName: pkgs.hydenix-themes.${themeName} or null;
```

`or null` があるため、タイプミスしてもビルドは成功し、そのテーマだけ入りません。
`demo/home.nix` の `"Some Theme"` は、この挙動を検証するためのテスト用エントリです。

**テーマが適用されないときは、まず名前のスペルを疑ってください。**
正しい名前は `pkgs/hydenix-themes/default.nix` のキーで確認できます
（`"Rosé Pine"` / `"Mac OS"` / `"Catppuccin-Macchiato"` のように表記が不規則です）。

なお、Hyprland の `animations.preset` などは逆に**存在しない名前でビルドが失敗します**。
挙動が統一されていない点に注意してください。

## 2. `cfg.vim or cfg.neovim` は論理和ではない

```nix
# modules/hm/editors.nix
(lib.mkIf (cfg.vim or cfg.neovim) {...})
```

Nix の `or` は**属性が存在しないときの既定値**を指定する演算子であり、論理和ではありません。
`cfg.vim` は常に存在する（既定値 `true` のオプション）ため、
この式は実質 `cfg.vim` だけを見ています。

論理和にしたいなら `||` を使います。

実害: `vim = false; neovim = true;` にすると、
neovim 用の wallbash 配色ファイルが配置されません。

## 3. `home.file` が同じファイル内に 2 回出てくる

`modules/hm/rofi.nix` には `home.file = {...};` が 2 回書かれています。

これはエラーになりません。Nix は「同じ属性パスに**属性集合リテラル**を 2 回代入した場合」は
自動でマージするからです（`{a = {x=1;}; a = {y=2;};}` → `{a = {x=1;y=2;};}`）。
値がリテラルでない場合（`{a = 1; a = 2;}`）はエラーになります。

`treefmt.nix` で statix の `repeated_keys` lint を無効化しているのは、この書き方があるためです。

## 4. 同じパスを複数モジュールが定義している

| パス | 定義しているファイル |
|---|---|
| `.config/kdeglobals` | `dolphin.nix` / `qt.nix` |
| `.config/menus/applications.menu` | `dolphin.nix` / `qt.nix` |
| `.config/electron-flags.conf` | `hyde.nix` / `social.nix` / `spotify.nix` |

**内容が完全に同じなのでマージされ、エラーになりません。**
ただし片方だけ変更するとその瞬間に定義衝突でビルドが落ちます。
どれか 1 つを編集するときは、他の定義箇所も揃える必要があります。

## 5. `nix` / `sddm` / `system` モジュールは `hydenix.enable` に従わない

```nix
# modules/system/nix.nix, sddm.nix, system.nix
enable = lib.mkOption {
  type = lib.types.bool;
  default = true;          # ← config.hydenix.enable ではない
  ...
};
```

他のモジュール（`boot` / `audio` / `hardware` / `network` / `gaming`）は
`default = config.hydenix.enable;` なので、親を切れば子も切れます。
しかしこの 3 つだけは `true` 固定です。

つまり `hydenix.enable = false;` にしても、
**SDDM・Hyprland・zsh・PipeWire 以外の共通パッケージは有効なまま**です。
本家からそのまま引き継がれている挙動で、意図的かどうかは不明です。

完全に切りたい場合は個別に指定します。

```nix
hydenix.system.enable = false;
hydenix.sddm.enable = false;
hydenix.nix.enable = false;
```

## 6. fish のエイリアスに Arch 用のものが残っている

```nix
# modules/hm/shell.nix
alias un='$aurhelper -Rns'
alias up='$aurhelper -Syu'
alias pl='$aurhelper -Qs'
```

`$aurhelper` は Arch Linux の AUR ヘルパーを指す変数で、NixOS には存在しません。
HyDE の設定をそのまま移植した名残であり、実行しても動きません。

## 7. シェル履歴の設定が `xdg.nix` にある

```nix
# modules/hm/xdg.nix
HISTFILE = "\${HISTFILE:-\$HOME/.zsh_history}";
HISTSIZE = "10000";
setopt_EXTENDED_HISTORY = "true";
```

本来は `shell.nix` にあるべき設定です。本家 issue #154 として残っている整理課題で、
フォークでも未対応です。動作上の問題はありません。

なお `setopt_*` という名前の環境変数を設定していますが、
これは zsh の `setopt` とは無関係で、HyDE 側のスクリプトが読む独自の変数です。

## 8. `mkHyprConfig` は生成物をすべて mutable にする

本家では `monitors.conf` だけが `mutable = true` で、
`keybindings.conf` などはリンクとして配置されていました。

フォークでは `mkHyprConfig` に統合された結果、
**`hypridle.conf` / `keybindings.conf` / `windowrules.conf` / `nvidia.conf` /
`hyprsunset.conf` もすべてコピーになりました**。

| | 利点 | 欠点 |
|---|---|---|
| mutable | 手で編集して `hyprctl reload` で即試せる | モジュールを切ってもファイルが残る |

実運用ではむしろ便利ですが、「設定から外したのに効いている」という混乱の原因になり得ます。

## 9. `assertions.nix` が `hyprsunset` を見ていない

`activeOverrides` と `assertions` のリストは、
`hypridle` / `keybindings` / `windowrules` / `nvidia` / `monitors` / `overrideMain` の
6 つしか列挙していません。

フォークで追加された `hyprsunset` は漏れているため、
`hyprsunset.overrideConfig = "";`（空文字）を書いても検証されず、警告も出ません。

## 10. `pyprland` はオプションごと消えている

本家では「`pyprland.nix` は存在するが `imports` に無い」という状態で、
オプションだけあって何も起きない、という分かりにくい挙動でした。

フォークでは `imports` のコメントアウトに加えて**オプション定義も無くなった**ため、
`hydenix.hm.hyprland.pyprland.*` を書くと未定義エラーで止まります。
黙って無視されるよりは親切な挙動です。

## 11. `hyde-diff-upstream` は master を rev に固定している

```nix
# pkgs/hyde-diff-upstream/default.nix
src = pkgs.fetchFromGitHub {
  rev = "master";
  sha256 = "sha256-cNOryXKFpVSTiAuzD0VQAV+2GQhJTTs1HBM6Z0cZoFo=";
};
```

`rev = "master"` は動く標的なので、上流が進むとハッシュが合わずビルドが失敗します。
使うときは `sha256` の更新が必要です（意図的に「その時点の master」を取る設計です）。

## 12. 名前の紛らわしい重複

| 名前 | 場所 | 中身 |
|---|---|---|
| `flake.nix` | ルート | hydenix 本体（**提供する側**） |
| `flake.nix` | `template/` | 利用者の雛形（**利用する側**） |
| `default.nix` | `pkgs/` | overlay の本体 |
| `default.nix` | `modules/hm/`, `modules/system/` | モジュールの入口 |
| `configuration.nix` | `demo/` | 開発者向けリファレンス設定 |
| `configuration.nix` | `template/` | 利用者が編集する設定 |
| `hardware-configuration.nix` | 両方 | どちらもダミー（実機では要置換） |
| `shell.nix` | ルート | devShell（`nix develop` 用） |
| `shell.nix` | `modules/hm/` | zsh/bash/fish の設定モジュール |

`demo/` は hydenix 自身の検証用であり、利用者が触る場所ではありません。

## 13. VM で試すときの注意

```bash
nix run github:florianvazelle/hydenix
```

- 設定を変えたら `rm hydenix.qcow2` でディスクイメージを消してから再実行する
  （消さないと古い状態が残る）
- KVM が使えない環境ではまともに動きません
- Hyprland が起動しない場合は
  [virtio ガイド](https://florianvazelle.github.io/hydenix/faq.html#how-do-i-run-hyprland-in-a-vm) を参照

## 14. 本家はメンテナンスモードに入っている

本家 richen604/hydenix は 2026-01-23 を最後に更新が止まっています。

このフォークの上流である florianvazelle/hydenix が実質的な後継で、
nixpkgs / home-manager / Hyprland / HyDE すべてを追従しています。

ただし保守者は 1 人なので、こちらも止まる可能性はあります。
その備えとして自分のフォークを挟んでいます（[09](./09-fork-workflow.md)）。
