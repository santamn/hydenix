# 00. 用語集

コードを読んでいて出てくる単語を、hydenix の文脈に沿って説明します。

## Nix まわり

| 用語 | 説明 |
|---|---|
| **Nix** | パッケージマネージャ兼、設定を記述するための関数型言語 |
| **NixOS** | Nix でシステム全体を管理する Linux ディストリビューション |
| **nixpkgs** | Nix のパッケージ集。10 万以上のパッケージ定義が入った巨大なリポジトリ |
| **flake** | 依存 (inputs) と成果物 (outputs) を宣言する仕組み。`flake.lock` にバージョンが固定される |
| **derivation** | 「ビルドの設計図」。`mkDerivation` で作る。ビルド結果は Nix ストアに入る |
| **Nix ストア** | `/nix/store/<ハッシュ>-<名前>/` にビルド結果が置かれる領域。**読み取り専用** |
| **overlay** | nixpkgs にパッケージを追加・上書きする関数。`final: prev: { ... }` の形 |
| **home-manager** | ユーザーのホームディレクトリ（dotfiles）を Nix で管理するツール |
| **モジュール** | `{ imports, options, config }` の形をした設定の単位。NixOS の設定はこれの集合体 |
| **activation script** | `nixos-rebuild` / `home-manager switch` のときに実行されるスクリプト |
| **stateVersion** | 「この設定を書き始めたバージョン」。データ移行の挙動を決める。原則変更しない |
| **substituter** | ビルド済みバイナリの配布サーバ。これがあると自前ビルドを回避できる |

## デスクトップまわり

| 用語 | 説明 |
|---|---|
| **HyDE** | Arch Linux 向けの Hyprland デスクトップ設定集。hydenix の元ネタ |
| **Hyprland** | タイル型の Wayland コンポジタ（ウィンドウマネージャ） |
| **Wayland** | X11 の後継となる画面表示プロトコル |
| **XWayland** | X11 用アプリを Wayland 上で動かす互換層 |
| **wallbash** | 壁紙の画像から色を抽出し、各アプリの配色を自動生成する HyDE の機能 |
| **UWSM** | Universal Wayland Session Manager。Wayland セッションを systemd で管理する |
| **waybar** | 画面上部のステータスバー |
| **rofi** | アプリランチャー。HyDE では壁紙選択・テーマ選択にも使う |
| **dunst** | デスクトップ通知の表示デーモン。代替として swaync も選べる |
| **awww** | Wayland 用の壁紙デーモン。本家が使っていた swww の置き換え |
| **hyprsunset** | 画面の色温度を下げる（ブルーライト低減）ツール。フォークで追加 |
| **SDDM** | ログイン画面（ディスプレイマネージャ） |
| **XDG ポータル** | アプリから画面共有やファイル選択を安全に行うための仲介役 |
| **dconf** | GNOME 系アプリの設定を保存するデータベース。D-Bus が必要 |

## hydenix 独自のもの

| 用語 | 説明 |
|---|---|
| **`mutable`** | hydenix が home-manager に足したオプション。詳細は [04](./04-mutable-files.md) |
| **`hydenix.*`** | システム側のオプション名前空間（`modules/system/`） |
| **`hydenix.hm.*`** | ユーザー側のオプション名前空間（`modules/hm/`） |
| **`mkHyprConfig`** | 「追記 or 置き換え」型の Hyprland モジュールを動的生成する関数。フォーク独自 |
| **hyde-shell** | HyDE の各種スクリプトを呼び出す入口コマンド |
| **hydectl** | HyDE の操作 CLI（Go 製・別リポジトリ） |
| **hyq (hyprquery)** | Hyprland の設定値を問い合わせる CLI |
| **hyde-ipc** | Hyprland のイベントを購読し、自動化する CLI（Rust 製） |
| **hyde-config** | `~/.config/hyde/config.toml` を解析して各設定へ反映するデーモン |
| **hyde-diff-upstream** | 固定中の HyDE と上流 master の差分を出すツール。フォーク独自 |
| **hyde-diff-home** | 固定中の HyDE と自分のホーム構成の差分を出すツール。フォーク独自 |

## 開発基盤まわり（フォークで追加）

| 用語 | 説明 |
|---|---|
| **treefmt** | 複数のフォーマッタを束ねて走らせるツール。`nix fmt` の実体 |
| **alejandra** | Nix コードのフォーマッタ。このリポジトリの整形規則 |
| **deadnix** | 使われていない変数・引数を検出する linter |
| **statix** | Nix のアンチパターンを検出する linter |
| **typos** | スペルミス検出。CI でリポジトリ全体を検査する |
| **zizmor** | GitHub Actions ワークフローの静的解析（セキュリティ） |
| **commitlint** | コミットメッセージが Conventional Commits に従っているか検査する |
| **renovate** | 依存関係の更新 PR を自動で作るボット |
