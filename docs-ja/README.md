# hydenix 日本語解説ドキュメント

このフォーク（`santamn/hydenix`）のコードを読んで理解するための補助資料です。コード中のコメントだけでは伝わりにくい、コードがなぜ今のようになっているのかという why の部分を中心にまとめています。

> [!IMPORTANT]
> **この `docs-ja/` とコード中の日本語コメントは `ja` ブランチにのみ存在します。**
> 修正の PR は `main` から分岐してください。`main` は日本語を含まないので、typos の CI が日本語混じりの英単語を誤検出せずに済み、利用側の flake から参照する先としてもこちらが正になります。運用手順は [09-fork-workflow.md](./09-fork-workflow.md) を参照。

## 読む順番

Nix 初心者の方は、上から順に読むことをおすすめします。

| # | ドキュメント | 内容 |
|---|------------|-----|
| 00 | [00-glossary.md](./00-glossary.md) | 用語集。知らない単語が出てきたらここへ |
| 01 | [01-architecture.md](./01-architecture.md) | 全体像。ファイルがどうつながっているか |
| 02 | [02-nix-basics.md](./02-nix-basics.md) | このリポジトリを読むのに必要な Nix の文法とモジュールシステム |
| 03 | [03-hyde-package.md](./03-hyde-package.md) | Arch 用の HyDE を NixOS 向けに変換する仕組み |
| 04 | [04-mutable-files.md](./04-mutable-files.md) | **最重要**: 読み取り専用の Nix と、書き換えたい HyDE の折り合いの付け方 |
| 05 | [05-theme-system.md](./05-theme-system.md) | テーマと wallbash（壁紙から配色を生成する仕組み） |
| 06 | [06-hyprland-modules.md](./06-hyprland-modules.md) | Hyprland 設定モジュールの設計パターン |
| 07 | [07-reading-notes.md](./07-reading-notes.md) | コードを読んで気づいた点・注意点 |
| 08 | [08-improvements.md](./08-improvements.md) | **将来加えると良い変更**。修正案と未解決問題の一覧 |
| 09 | [09-fork-workflow.md](./09-fork-workflow.md) | ブランチ構成と PR の運用（日本語コメントの扱い） |
| 10 | [10-ci.md](./10-ci.md) | CI（GitHub Actions）が何を検証し、何を自動化しているか |

## 3 分で分かる要約

hydenix は **Arch Linux 用のデスクトップ設定集である HyDE を、NixOS で宣言的に使えるようにしたもの** です。

本質的な難しさは 1 点に集約されます。

> Nix は「設定ファイルは読み取り専用のシンボリックリンク」を前提にする。
> HyDE は「テーマを切り替えるとスクリプトが設定ファイルを書き換える」を前提にする。

この矛盾を解消するために、hydenix は以下の 3 つの仕掛けを持っています。

1. **HyDE 本体をビルド時に書き換える** ([03](./03-hyde-package.md)): Arch 前提のコマンド名やパスを、NixOS 用に `substituteInPlace` で置換してからパッケージ化する
2. **`mutable` オプション** ([04](./04-mutable-files.md)): 書き換えが必要なファイルだけ、リンクではなく「書き込み可能なコピー」として配置する
3. **activation script + systemd サービス** ([05](./05-theme-system.md)): テーマ適用スクリプトを、rebuild 時とログイン後の 2 段階で実行する

この 3 つが分かれば、hydenix のコードはほぼ読めます。

## このフォークの立ち位置

```text
richen604/hydenix          本家。2026-01-23 を最後にアーカイブ（読み取り専用）
        ↓ fork
florianvazelle/hydenix     後継だったが、2026-08 にアーカイブ（読み取り専用）
        ↓ fork
santamn/hydenix            ← このリポジトリ
```

## 本家からの主な変更点

本家（richen604/hydenix）を読んだことがある人向けの差分です。

### ディレクトリ構成

| 本家 | このフォーク |
|-----|------------|
| `hydenix/modules/system/` | `modules/system/` |
| `hydenix/modules/hm/` | `modules/hm/` |
| `hydenix/sources/` | `pkgs/`（`overlay.nix` → `default.nix`、`themes/` → `hydenix-themes/`） |
| `lib/config/` + `lib/vms/` | `demo/` |
| `lib/dev-shell.nix` | `shell.nix` |
| `lib/hyde-update/` | `pkgs/hyde-diff-upstream/` + `pkgs/hyde-diff-home/` |
| `template/docs/` | `docs/`（mdbook + GitHub Pages） |
| nixfmt-rfc-style | **alejandra**（treefmt 経由。CI ではチェックしていない） |

### モジュール

- `git.nix` が削除された。本家 issue #169 の型バグをモジュールごと消して解決している。git の設定は素の `programs.git` に書く
- `swww.nix` が `awww.nix` になった（壁紙デーモンの差し替え）
- Hyprland の設定が Lua になった（HyDE v26.08.21 に合わせたもの）。hydenix は `~/.config/hypr/hyprland.lua` を書き、`hydenix.hm.hyprland.extraConfig` と `overrideMain` は Lua を受け取る
- 追記か置き換えを選ぶ型の hyprland モジュールが `utils/mkHyprConfig.nix` に一本化された。`hypridle`、`hyprlock`、`hyprsunset` は同じ構造なので、個別ファイルをやめて関数生成に変わった。`keybindings`、`monitors`、`nvidia`、`windowrules` のオプションは無く、`extraConfig` の Lua に書く
- hyprlock が `hyprland/` の下に入り、`hydenix.hm.hyprland.hyprlock.enable` で切り替える。`lockscreen.nix` と swaylock は無い
- `hyprsunset` が追加された（ブルーライト低減）
- `pyprland` が外された。モジュールとオプションは無い
- `mutable = true` のファイルは、設定から外すと次の世代でホームから削除される
- テーマに同梱のアイコン・GTK テーマ・フォントは `~/.local/share/{icons,themes,fonts}` に置かれる。同じ名前のディレクトリを複数のテーマが持つときは、先に書いたテーマのディレクトリを丸ごと使う（中身の違うアイコンテーマは、後のテーマの分をプロファイルへ入れる）
- zsh の履歴設定は `xdg.nix` の環境変数ではなく `programs.zsh.history` で書く（本家 issue #154）
- `hyprland.systemd.*` が追加された。Hyprland 起動時に環境変数を systemd / D-Bus のユーザ環境へ流し込み、`hyprland-session.target` を起動する

### flake

- `nixosModules.default` が **home-manager 本体と `homeModules.default` を自動で配線する**（`home-manager.sharedModules` 経由）。本家より利用者側の記述が減る
- `homeConfigurations.default` が追加され、home-manager 単体でも使える
- Hyprland は本家と同じく nixpkgs のものを使う。ただし nixpkgs は nixos-unstable を追い（`flake.lock` を週次で更新）、`modules/system/system.nix` の assertion が、HyDE の対応する major.minor（今は 0.57）以外の Hyprland を評価時に止める
- `nix` / `sddm` / `system` の各モジュールも、ほかのシステムモジュールと同じく `hydenix.enable` に従う
- `hostname` / `timezone` / `locale` に既定値が付き、`lib.mkIf cfg.enable (lib.mkDefault ...)` になった（本家は `mkDefault` なし＋必須アサーションあり）。`system.stateVersion` と `home.stateVersion` も `mkDefault` なので、利用者の書いた値が勝つ

### 開発基盤

- treefmt（alejandra / deadnix / statix）による整形（`nix fmt`。CI では実行しない）と、typos・zizmor による CI
- renovate と Dependabot による依存の自動更新と自動マージ、テーマなどのブランチピンの自動更新（[10](./10-ci.md)）
- PR と push 前の手順をまとめた `AGENTS.md`（`CLAUDE.md` から読み込む）
- `docs/` を mdbook 化して GitHub Pages で公開

## 公式ドキュメント（英語）

- [インストール手順](https://santamn.github.io/hydenix/installation.html)
- [設定オプション一覧](https://santamn.github.io/hydenix/options.html)
- [FAQ](https://santamn.github.io/hydenix/faq.html)
- [トラブルシューティング](https://santamn.github.io/hydenix/troubleshooting.html)

リポジトリ内では [`docs/src/`](../docs/src/) にソースがあります。
