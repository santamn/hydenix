# PR A: カーソル/アイコンテーマを nixpkgs 由来にする

- ブランチ: `fix/theme-assets-from-nixpkgs`（3 コミット）
- タイトル案: `fix(pkgs): build cursor and icon themes from nixpkgs sources`
- 差分: <https://github.com/florianvazelle/hydenix/compare/main...santamn:hydenix:fix/theme-assets-from-nixpkgs>

---

## Description

### 問題

`pkgs.Bibata-Modern-Ice` がビルドできず、hyde の home-manager モジュールを含むリビルドがすべて失敗する。このパッケージと `pkgs.Tela-circle-dracula` は、HyDE リポジトリの**ブランチ head** から pre-built tarball を `fetchurl` しているが、HyDE が master から `Source/arcs/Cursor_BibataIce.tar.gz` を削除したため（HyDE commit `b8cc647`、2026-07-27）、Bibata の URL が 404 になった。Tela の URL は今のところ生きているが、同じくブランチ head 参照なのでいつ消えてもおかしくない。HyDE 自身はすでに `ful1e5/Bibata_Cursor` v2.0.7 のリリースを直接取得する方式に移行しており、同梱アーカイブは deprecated 扱い。

URL を commit に pin し直す選択肢もあるが、HyDE がもう配布していない成果物に固定することになり、Renovate も `scripts/update-themes.sh` もこれらのファイルを追跡しないため、二度と更新されないパッケージが残る。

### 変更内容（コミット順）

**1. `fix(pkgs): build cursor and icon themes from nixpkgs sources`**

両テーマを nixpkgs から構築する。`bibata-cursors` は HyDE が pin しているのと同じ `ful1e5/Bibata_Cursor` v2.0.7 をビルドし、`tela-circle-icon-theme.override { colorVariants = ["dracula"]; }` は同じ upstream (`vinceliuice/Tela-circle-icon-theme`) の dracula バリアントをビルドする。更新は手書きの URL + hash ではなく flake.lock 経由になる（`update-flake-lock.yml` と Renovate の `lockFileMaintenance` が既に面倒を見ている）。overlay の属性名は不変なので `modules/hm/hyde.nix` や `modules/system/sddm.nix` への変更は不要。

- `bibata-cursors` は 12 バリアント同梱（337 MB）なので `Bibata-Modern-Ice` のみコピーして 33 MB に抑えた
- nixpkgs は XCursor のみビルドするため、旧アーカイブが同梱していた hyprcursor バリアントは `hyprcursor-util` で XCursor から再生成する（さらに別のサードパーティ配布物を pin するより、`bibata-cursors` の内容と常に同期する）。shape 数 56・hotspot・override は旧アーカイブと一致し、差は画像形式のみ（SVG 1 枚 → PNG 14 サイズ、bilinear リサイズ）

**2. `fix(pkgs): reuse the standalone icon/cursor themes in HyDE themes`**

1 の結果、HyDE テーマの tarball が同梱する同名テーマのコピー（例: Catppuccin Mocha の `Icon_TelaDracula.tar.gz`）と standalone パッケージの中身が食い違う。両方が `home.packages` に入ると、home-manager の `buildEnv` は内容の異なる同一パス `share/icons/<name>` のマージを拒否するため、`home-manager switch` が icon-theme.cache の衝突で失敗する。これまで動いていたのは両者が同じ tarball 由来で byte 単位に一致していたからで、#1 だけをマージすると main が壊れる。このため同一 PR に含めている。

`mkTheme` が `sharedAssets`（standalone パッケージの attrset、tarball の展開先ディレクトリ名がキー）を受け取り、展開後に該当ディレクトリを standalone パッケージへの symlink に置き換える。両者が同一 store path に解決するので `buildEnv` が受理し、各テーマは 1 回だけビルドされる。ディレクトリ名をキーにするのは、それがまさに `buildEnv` が衝突する条件であり、tarball のファイル名は当てにならないため（Joker は同じテーマを `Icon_Tela-circle-dracula.tar.gz` として同梱している）。全 58 テーマの調査で、対象は Tela-circle-dracula を同梱する 5 テーマと Bibata-Modern-Ice を同梱する Vanta Black で、いずれもこの置換で解決する。

あわせて `meta.priority` の無条件 inherit をやめた。どのテーマも `priority` を定義しておらず、評価すると throw する属性が `buildEnv` の `meta.priority or <default>` を破壊する（これまで顕在化しなかったのは、テーマが `lndir` ベースの `symlinkJoin` にしか渡されず `meta` が読まれなかったため）。

**3. `ci: build theme assets in flake checks`**

これらのパッケージは fixed-output derivation で fetch はビルド時にしか走らないため、URL が死んでいた間も `nix flake check` は green のままだった。`hyde` と両テーマパッケージを `checks` に追加してビルドし、PR の段階で落ちるようにする。さらに `home.packages` と同じ `buildEnv` マージをデフォルトテーマセット（`hydenix.hm.theme.themes` のデフォルト値 = Catppuccin Mocha/Latte）に対して行う `theme-assets` check を追加し、2 のような衝突も CI で検出する。`symlinkJoin` では検出できない（`lndir` は衝突時に警告を出すだけ）。

## Type of change

- [x] Bug fix (non-breaking change which fixes an issue)

## Checklist

- [x] My commits follow conventional commit format
- [x] I have updated the documentation accordingly — n/a（ユーザー向けオプションの変更なし）
- [x] My changes generate no new warnings

---

## 提出時メモ（PR 本文には含めない）

- 旧 #3/#4/#5 の統合。#4 は #3 への 1 行コメント追加（fixup 済み）、#5 は #3 単独では main が壊れるため同一 PR に統合
- 旧 #3 にあった weekly cron (`schedule:`) は削除した。上流の Actions 課金・通知が増える変更で主題とも別のため。必要だと思うなら「Bibata の URL が実際に 404 になった経緯があり、PR が開いていない期間の破損検知のため weekly 実行を提案する」と PR コメントで別途提案するとよい
- `theme-assets` check の対象は `hydenix.hm.theme.themes` のデフォルト値と明示的に対応させた（全テーマをビルドするとCI時間が大きく伸びるため不採用）
