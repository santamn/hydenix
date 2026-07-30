# 07. 読解メモ — 気づいた点と落とし穴

コードを読む上での注意点をまとめました。いずれもコードの挙動を変えるものではなく、読み手向けの注意書きです。

直すべき問題として整理したものは [08-improvements.md](./08-improvements.md) にあります。この文章は仕様として知っておけばよいことが中心です。

> [!NOTE]
> 手元の環境に `nix` が無いため、以下はコードの読解に基づく指摘です。実際のビルド・動作までは確認していません。

## 1. 存在しないテーマ名は黙って無視される

```nix
findThemeByName = themeName: pkgs.hydenix-themes.${themeName} or null;
```

`or null` があるため、タイプミスしてもビルドは成功し、そのテーマだけ入りません。`demo/home.nix` の `"Some Theme"` は、この挙動を検証するためのテスト用エントリです。

テーマが適用されないときは、まず名前のスペルを疑ってください。正しい名前は `pkgs/hydenix-themes/default.nix` のキーで確認できます。（`"Rosé Pine"` / `"Mac OS"` / `"Catppuccin-Macchiato"` のように表記が不規則です）。

なお、Hyprland の `animations.preset` などは逆に存在しない名前でビルドが失敗します。挙動が統一されていない点に注意してください。

## 2. `cfg.vim or cfg.neovim` は論理和ではない

```nix
# modules/hm/editors.nix
(lib.mkIf (cfg.vim or cfg.neovim) {...})
```

Nix の `or` は**属性が存在しないときの既定値**を指定する演算子であり、論理和ではありません。`cfg.vim` は常に存在する（既定値 `true` のオプション）ため、この式は実質 `cfg.vim` だけを見ています。論理和にしたいなら `||` を使います。

**実害**: `vim = false; neovim = true;` にすると、neovim 用の wallbash 配色ファイルが配置されません。

修正案は [08-B-6](./08-improvements.md) に書いています。

## 3. `home.file` が同じファイル内に 2 回出てくる

`modules/hm/rofi.nix` には `home.file = {...};` が 2 回書かれています。

Nix では同じ属性パスに属性集合リテラルを2回代入した場合、自動でマージされるため（`{a = {x=1;}; a = {y=2;};}` → `{a = {x=1;y=2;};}`）、エラーにはなりません。値がリテラルでない場合（`{a = 1; a = 2;}`）はエラーになります。

`treefmt.nix` で statix の `repeated_keys` lint を無効化しているのは、この書き方があるためです。

## 4. 同じパスを複数モジュールが定義している

| パス | 定義しているファイル |
|-----|-------------------|
| `.config/kdeglobals` | `dolphin.nix` / `qt.nix` |
| `.config/menus/applications.menu` | `dolphin.nix` / `qt.nix` |
| `.config/electron-flags.conf` | `hyde.nix` / `social.nix` / `spotify.nix` |

内容が完全に同じなのでマージされ、エラーになりません。ただし片方だけ変更するとその瞬間に定義衝突でビルドが落ちます。どれか1つを編集するときは、他の定義箇所も揃える必要があります。

## 5. `nix` / `sddm` / `system` モジュールは `hydenix.enable` に従わない

```nix
# modules/system/nix.nix, sddm.nix, system.nix
enable = lib.mkOption {
  type = lib.types.bool;
  default = true;          # ← config.hydenix.enable ではない
  ...
};
```

他のモジュール（`boot` / `audio` / `hardware` / `network` / `gaming`）は`default = config.hydenix.enable;` なので、親を切れば子も切れます。しかしこの 3 つだけは `true` 固定です。

つまり `hydenix.enable = false;` にしても、**SDDM・Hyprland・zsh・PipeWire 以外の共通パッケージは有効なまま**です。本家からそのまま引き継がれている挙動で、意図的かどうかは不明です。

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
# ほかに pa / pc / po の計 6 個
```

`$aurhelper` は Arch Linux の AUR ヘルパーを指す変数です。上流 HyDE の `user.fish` には `set aurhelper yay` がありますが、home-manager が `interactiveShellInit` を `status is-interactive; and begin … end` で包むため、スコープ指定の無い `set` はブロックを抜けた時点で消えます。エイリアス（＝関数）だけが残り、プロンプトでは `$aurhelper` が空になります。

そもそも `yay` は NixOS にないので、どちらにせよ動きません。なお上流ではこの 6 行はコメントアウトされており、有効化したのは hydenix 側です。

削除する修正は [08-B-9](./08-improvements.md) に書いています。

## 7. シェル履歴の設定が `xdg.nix` にある

```nix
# modules/hm/xdg.nix
HISTFILE = "\${HISTFILE:-\$HOME/.zsh_history}";
HISTSIZE = "10000";
setopt_EXTENDED_HISTORY = "true";
```

本来は `shell.nix` にあるべき設定です。本家 issue #154 として残っている整理課題で、フォークでも未対応です。動作上の問題はありません。

なお `setopt_*` という名前の環境変数は zsh の `setopt` とは無関係で、HyDE 側の独自変数です。ただし**ピン留め中の HyDE には読み手がもう存在しません**。`HISTFILE` / `HISTSIZE` / `SAVEHIST` のほうも home-manager の zsh モジュールが `.zshrc` で上書きするため、この 9 行は 1 行も効いていません。

移動と削除の両方を [08-C-2](./08-improvements.md#c-2-履歴の環境変数を-shellnix-へ移す本家-issue-154) に書いています。

## 8. `mkHyprConfig` は生成物をすべて mutable にする

本家では `monitors.conf` だけが `mutable = true` で、`keybindings.conf` などはリンクとして配置されていました。

フォークでは `mkHyprConfig` に統合された結果、`hypridle.conf` / `keybindings.conf` / `windowrules.conf` / `nvidia.conf` /
`hyprsunset.conf` もすべてコピーになりました。

|         | 利点 | 欠点 |
|---------|-----|------|
| mutable | 手で編集して `hyprctl reload` で即試せる | モジュールを切ってもファイルが残る |

実運用ではむしろ便利ですが、設定から外したのに効いているという混乱の原因になり得ます。

## 9. `assertions.nix` が `hyprsunset` を見ていない

`activeOverrides` と `assertions` のリストは、`hypridle` / `keybindings` / `windowrules` / `nvidia` / `monitors` / `overrideMain` の6つしか列挙していません。

フォークで追加された `hyprsunset` は漏れているため、`hyprsunset.overrideConfig = "";`（空文字）を書いても検証されず、警告も出ません。

## 10. `pyprland` はオプションごと消えている

本家では`pyprland.nix` は存在するが `imports` に無いという状態で、オプションだけあって何も起きない、という分かりにくい挙動でした。

フォークでは `imports` のコメントアウトに加えて**オプション定義も無くなった**ため、`hydenix.hm.hyprland.pyprland.*` を書くと未定義エラーで止まります。黙って無視されるよりは親切な挙動です。

## 11. `hyde-diff-upstream` は master を rev に固定している

```nix
# pkgs/hyde-diff-upstream/default.nix
src = pkgs.fetchFromGitHub {
  rev = "master";
  sha256 = "sha256-cNOryXKFpVSTiAuzD0VQAV+2GQhJTTs1HBM6Z0cZoFo=";
};
```

`rev = "master"` は動く標的なので、上流が進むとハッシュが合わずビルドが失敗します。使うときは `sha256` の更新が必要です（意図的に「その時点の master」を取る設計です）。

## 12. 名前の紛らわしい重複

| 名前 | 場所 | 中身 |
|-----|------|-----|
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

- 設定を変えたら `rm hydenix.qcow2` でディスクイメージを消してから再実行する: 消さないと古い状態が残る
- KVM が使えない環境ではまともに動きません
- Hyprland が起動しない場合は[virtio ガイド](https://florianvazelle.github.io/hydenix/faq.html#how-do-i-run-hyprland-in-a-vm) を参照

## 14. 本家はメンテナンスモードに入っている

本家 richen604/hydenix は 2026-01-23 を最後に更新が止まっています。

このフォークの上流である florianvazelle/hydenix が実質的な後継で、nixpkgs / home-manager / Hyprland / HyDE すべてを追従しています。

ただし保守者は 1 人なので、こちらも止まる可能性はあります。その備えとして自分のフォークを挟んでいます（[09](./09-fork-workflow.md)）。
