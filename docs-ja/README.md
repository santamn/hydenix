# hydenix 日本語解説ドキュメント

このフォーク（`santamn/hydenix`）のコードを読んで理解するための補助資料です。コード中のコメントだけでは伝わりにくいなぜそうなっているのかということを中心にまとめています。

> [!IMPORTANT]
> **この `docs-ja/` とコード中の日本語コメントは `ja` ブランチにのみ存在します。**
> 上流（florianvazelle/hydenix）へ PR を送るときは `main` から分岐してください。運用手順は [09-fork-workflow.md](./09-fork-workflow.md) を参照。

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
| 07 | [07-reading-notes.md](./07-reading-notes.md) | コードを読んで気づいた点・落とし穴 |
| 08 | [08-improvements.md](./08-improvements.md) | **将来加えると良い変更**。修正案と未解決問題の一覧 |
| 09 | [09-fork-workflow.md](./09-fork-workflow.md) | 上流追従と PR の運用（日本語コメントの扱い） |
| 10 | [10-ci.md](./10-ci.md) | CI（GitHub Actions）が何を検証し、何を自動化しているか |

## 3 分で分かる要約

hydenix は **Arch Linux 用のデスクトップ設定集である HyDE を、NixOS で宣言的に使えるようにしたもの** です。

本質的な難しさは 1 点に集約されます。

> Nix は「設定ファイルは読み取り専用のシンボリックリンク」を前提にする。
> HyDE は「テーマを切り替えるとスクリプトが設定ファイルを書き換える」を前提にする。

この矛盾を解消するために、hydenix は以下の 3 つの仕掛けを持っています。

1. **HyDE 本体をビルド時に書き換える** ([03](./03-hyde-package.md)): Arch 前提のコマンド名やパスを、NixOS 用に `sed` で置換してからパッケージ化する
2. **`mutable` オプション** ([04](./04-mutable-files.md)): 書き換えが必要なファイルだけ、リンクではなく「書き込み可能なコピー」として配置する
3. **activation script + systemd サービス** ([05](./05-theme-system.md)): テーマ適用スクリプトを、rebuild 時とログイン後の 2 段階で実行する

この 3 つが分かれば、hydenix のコードはほぼ読めます。

## このフォークの立ち位置

```
richen604/hydenix          本家。2026-01-23 を最後に停止（メンテナンスモード）
        ↓ fork
florianvazelle/hydenix     実質的な後継。nixpkgs / HyDE / Hyprland を追従中
        ↓ fork
santamn/hydenix            ← このリポジトリ
```

自分のフォークを挟んでいるのは、florianvazelle 氏が 1 人で保守しているため、止まった場合に即座に自分で前へ進められるようにするためです。普段は `git merge upstream/main` するだけで済みます（[09](./09-fork-workflow.md)）。

## 本家からの主な変更点

本家（richen604）を読んだことがある人向けの差分です。

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
| nixfmt-rfc-style | **alejandra**（treefmt 経由、CI で強制） |

### モジュール

- **`git.nix` が削除された** — 本家 issue #169 の型バグをモジュールごと消して解決。git の設定は素の `programs.git` に書く
- **`swww.nix` → `awww.nix`** — 壁紙デーモンの差し替え
- **hyprland モジュールが `utils/mkHyprConfig.nix` に一本化された** — `hypridle` / `keybindings` / `monitors` / `nvidia` / `windowrules` は同じ構造だったため、個別ファイルをやめて関数生成に変わった。オプション名と使い方は本家と同じ
- **`hyprsunset` が追加された** — ブルーライト低減
- **`pyprland` が無効化された** — `default.nix` の imports でコメントアウトされ、オプションも消えている
- **`hyprland.systemd.*` が追加された** — Hyprland 起動時に環境変数を systemd / D-Bus のユーザ環境へ流し込み、`hyprland-session.target` を起動する

### flake

- `nixosModules.default` が **home-manager 本体と `homeModules.default` を自動で配線する**（`home-manager.sharedModules` 経由）。本家より利用者側の記述が減る
- `homeConfigurations.default` が追加され、home-manager 単体でも使える
- Hyprland を flake input で `v0.55.4` に固定し、cachix を `nixConfig` に追加
- `hostname` / `timezone` / `locale` に既定値が付き、`lib.mkIf cfg.enable (lib.mkDefault ...)` になった（本家は `mkDefault` なし＋必須アサーションあり）

### 開発基盤

- treefmt（alejandra / deadnix / statix）、typos、zizmor による CI
- renovate による依存自動更新、テーマの sha256 自動更新
- `docs/` を mdbook 化して GitHub Pages で公開

## 公式ドキュメント（英語）

- [インストール手順](https://florianvazelle.github.io/hydenix/installation.html)
- [設定オプション一覧](https://florianvazelle.github.io/hydenix/options.html)
- [FAQ](https://florianvazelle.github.io/hydenix/faq.html)
- [トラブルシューティング](https://florianvazelle.github.io/hydenix/troubleshooting.html)

リポジトリ内では [`docs/src/`](../docs/src/) にソースがあります。
