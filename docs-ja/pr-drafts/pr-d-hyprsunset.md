# PR D: hyprsunset を設定と一緒にインストールする

- ブランチ: `fix/hyprsunset-missing-package`（1 コミット、diff は 1 行）
- タイトル案: `fix(hm): install hyprsunset alongside its config`
- 差分: <https://github.com/florianvazelle/hydenix/compare/main...santamn:hydenix:fix/hyprsunset-missing-package>

---

## Description

### 問題

Hyprland セッションを開始するたびに critical の通知が出る:

```
Error
Executable not found: 'hyprsunset'
```

blue light filter は一度も起動せず、waybar の `custom/hyprsunset` ボタンと swaync の "blue light filter" アクションも死んでいる。

### 原因

`hyprsunset` バイナリを参照するものは hydenix が 3 つ出荷している（`startup.conf` の `exec-once`、`mkHyprConfig` が書く `~/.config/hypr/hyprsunset.conf`、waybar の `custom-hyprsunset` モジュール）のに、パッケージ自体をどこもインストールしていない。`mkHyprConfig` は `home.file` を書くだけでパッケージを追加しないため、設定とボタンだけが存在する。セッション開始時に HyDE の `app2unit.sh` が `command -v hyprsunset` に失敗して上記の通知を出す。

### 修正

設定を生成しているモジュールでパッケージをインストールする（1 行）:

```nix
(lib.mkIf cfg.hyprsunset.enable pkgs.hyprsunset)
```

`hydenix.hm.hyprland.hyprsunset.enable` は `mkHyprConfig` が既に生成しているオプションなので新規オプションは増えず、設定をオフにしたユーザーにはパッケージも入らない。`modules/hm/lockscreen.nix` が `hyprlock`/`swaylock` を同じ `lib.mkIf` パターンで設定とペアにしているのに合わせた。`startup.conf` が起動するもう 1 つのデーモン `hypridle` は `modules/system/system.nix` が既に提供しており、`hyprsunset` だけがパッケージの無い残りだった。

### 検証

リビルド後の新しいセッションで:

```bash
command -v hyprsunset
systemctl --user status "hyde-$XDG_SESSION_DESKTOP-blue-light-filter.service"
hyprctl hyprsunset temperature
```

セッション開始時に "Executable not found" の通知が出ず、waybar のトグルで画面色温度が変わることを実機で確認済み。`hyprsunset` は nixpkgs にあるため新しい flake input は不要。

## Type of change

- [x] Bug fix (non-breaking change which fixes an issue)

## Checklist

- [x] My commits follow conventional commit format
- [x] I have updated the documentation accordingly — n/a（既存オプションの挙動を完成させるだけ）
- [x] My changes generate no new warnings

---

## 提出時メモ（PR 本文には含めない）

- 旧 #6 と同一内容（upstream/main にクリーンに適用できる）
