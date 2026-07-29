# 08. 将来加えると良い変更

「直したほうがよい」と判断した箇所の一覧です。
上のものほど優先度が高く、下にいくほど「踏んでも仕様」と割り切れるものになります。

各項目は **問題 → なぜ起きる → どう直す** の順で書いています。

> [!NOTE]
> 手元の環境に `nix` が無いため、以下はコードの読解に基づく指摘です。
> 実機で確認してから PR を出してください。

---

## A. 優先度: 高

### A-1. `mutableGeneration` — 存在しない依存名を参照している

**問題**: 3 つの activation script が、実在しないエントリを待っている。

| ファイル | エントリ名 |
|---|---|
| `modules/hm/theme.nix` | `home.activation.setTheme` |
| `modules/hm/hyde.nix` | `home.activation.createCavaConfig` |
| `modules/hm/hyprland/default.nix` | `home.activation.createHyprConfigs` |

該当箇所は次のコマンドで一覧できます。

```bash
grep -rn 'entryAfter \["mutableGeneration"\]' modules/
```

いずれも `lib.hm.dag.entryAfter ["mutableGeneration"]` と書かれていますが、
`modules/hm/mutable.nix` が実際に定義しているのは **`mutableFileGeneration`** です。

**なぜ起きるか**: home-manager の DAG は**存在しない依存名を黙って無視します**。
エラーにならないため誰も気づきませんが、
「mutable ファイルのコピー後に実行する」という意図した順序制約が**一切効いていません**。
実行位置は toposort の実装依存で決まっており、home-manager の更新で順番が変わり得ます。

**実害**: `setTheme` が、mutable なスクリプト本体（`~/.local/lib/hyde/theme.switch.sh`）の
コピー完了前に走る可能性があります。現状は `writeBoundary` などの他の制約で
結果的に順序が保たれている可能性が高く、これが原因で壊れているという確証はありません。
**潜在的な問題**という位置づけです。

**直し方**: 3 か所の文字列を変えるだけ。

```diff
-home.activation.setTheme = lib.hm.dag.entryAfter ["mutableGeneration"] ''
+home.activation.setTheme = lib.hm.dag.entryAfter ["mutableFileGeneration"] ''
```

**リスクは無し**。`mutable.nix` の `config` は `enable` フラグで囲われていない（無条件）ので、
このエントリは常に存在します。依存先が消えることはありません。

> この修正は上流へ PR を送る価値があります。手順は [09-fork-workflow.md](./09-fork-workflow.md) を参照。

### A-2. activation script が `$DRY_RUN_CMD` を使っていない

**問題**: A-1 と同じ 3 つのスクリプトが、`mkdir` / `touch` / `chmod` や
`theme.switch.sh` の実行を生のコマンドで書いています。

```nix
home.activation.createCavaConfig = lib.hm.dag.entryAfter [...] ''
  mkdir -p "$HOME/.config/cava"      # ← $DRY_RUN_CMD が無い
  touch "$HOME/.config/cava/config"
  chmod 644 "$HOME/.config/cava/config"
'';
```

**なぜ起きるか**: home-manager は `$DRY_RUN_CMD` という変数を用意しており、
`--dry-run` 相当のときは `echo` に、通常時は空文字になります。
これを付けずに書いたコマンドは、**dry-activate でも実際に実行されます**。

`mutable.nix` は正しく `$DRY_RUN_CMD` を使っているので、対比すると分かりやすいです。

**実害**: `nixos-rebuild dry-activate` が副作用を持つ。
テーマ適用まで走るので、確認のつもりが本番適用になります。

**直し方**:

```diff
-  mkdir -p "$HOME/.config/cava"
+  $DRY_RUN_CMD mkdir -p "$HOME/.config/cava"
```

> [!IMPORTANT]
> **A-1 とは別の PR にしてください。** 最初の PR は小さく保つのが通りやすさの鉄則です。
> A-1 は文字列 3 か所でリスクゼロ、A-2 は挙動の変更を含むため議論が要ります。

### A-3. `mutable` ファイルが「設定から消しても残る」

**問題**: `mutable = true` のファイルはコピーなので home-manager の管理外です。
設定から外してもホームに残り続け、手動削除が必要です。

これは仕組み上の必然（[04](./04-mutable-files.md) 参照）ですが、
**実運用でいちばん効く問題**です。特にフォークでは `mkHyprConfig` の生成物が
すべて mutable になったため、影響範囲が本家より広がっています。

**当面の対処**: おかしくなったらリセットする。

```bash
rm -rf ~/.config/hyde ~/.local/share/hyde ~/.cache/hyde
# その後 nixos-rebuild switch で再配置される
```

**根本的な直し方（未実装・本家 TODO）**:

- `mutable.enable` … 機能そのものを切れるようにする
- `mutable.mode` … `initOnly`（初回だけコピー）と `replace`（毎回上書き）を選べるようにする
- 前世代の mutable ファイル一覧を記録し、設定から消えたものを自動削除する
- generation ロールバック時に mutable ファイルも戻す

3 つ目が本命ですが、「ユーザーが手で編集した内容を消してよいか」の判断が難しく、
設計上の議論が必要です。**大きめの変更なので、上流に投げる前に issue で相談するのが無難です。**

---

## B. 優先度: 中

### B-1. `hydectl` の `mainProgram` が間違っている

```nix
# pkgs/hydectl/default.nix
meta = with lib; {
  ...
  mainProgram = "hyde-ipc";   # ← 正しくは "hydectl"
};
```

`pkgs/hyde-ipc/default.nix` からのコピペと思われます。

**実害**: `nix run .#hydectl` が `hydectl` ではなく `hyde-ipc` を起動しようとします
（`$out/bin/hyde-ipc` は存在しないのでエラーになります）。

**直し方**: `mainProgram = "hydectl";` に変更。1 行。**PR 向きの小さな修正です。**

### B-2. `hyde-gallery` の `sha256` が空

```nix
# pkgs/hyde-gallery/default.nix
sha256 = "";
```

**実害**: このパッケージはビルドできません。
overlay には `hyde-gallery` として登録され、`flake.nix` の `packages` にも
`inherit (pkgs) ... hyde-gallery;` として入っているので、
`nix build .#hyde-gallery` は失敗します。

日常的に参照されないため表面化していないだけです。

**直し方の選択肢**:

1. 正しい `sha256` を入れる（`nix-prefetch-git` で取得）
2. 使っていないので**削除する**

実際のテーマは `pkgs/hydenix-themes/` 以下で個別に取得しており、
`hyde-gallery` を参照しているコードは 1 つもありません。**2 が妥当だと思います。**

### B-3. `assertions.nix` が `hyprsunset` を検証していない

**問題**: フォークで `hyprsunset` を追加したときに、
`assertions.nix` の 2 つのリスト（`activeOverrides` と `assertions`）への追加が漏れています。

**実害**: `hyprsunset.overrideConfig = "";`（空文字）を書いても弾かれず、
override 使用中の警告も出ません。

**直し方**: 他の 5 つと同じ行を 2 か所に足すだけ。

```nix
(lib.optionalString (cfg.hyprsunset.overrideConfig != null) "hyprsunset.overrideConfig")
```

```nix
{
  assertion = cfg.hyprsunset.overrideConfig == null || cfg.hyprsunset.overrideConfig != "";
  message = "hydenix.hm.hyprland.hyprsunset.overrideConfig is set but empty. ...";
}
```

**より良い直し方**: `mkHyprConfig` を使っている以上、
assertion も `mkHyprConfig` 側で生成すべきです。そうすればモジュール追加時の漏れが構造的に無くなります。
こちらのほうが PR としては筋が良いですが、変更範囲は大きくなります。

### B-4. `stateVersion` に `mkDefault` が無い

```nix
# modules/system/default.nix
system.stateVersion = "25.05";

# modules/hm/default.nix
home.stateVersion = "25.05";
```

**なぜ問題か**: 利用者側も自分の `configuration.nix` / `home.nix` で
`stateVersion` を書くのが普通です。型のマージが `mergeEqualOption`
（値が全て等しければ通る）なので、**両方が `"25.05"` である限りエラーになりません**。
しかし片方でも変えた瞬間に定義衝突でビルドが落ちます。

そもそも `stateVersion` は「利用者がいつ環境を作ったか」を表す値なので、
ライブラリ側が固定値を主張するのは筋が悪いです。

**直し方**: `lib.mkDefault` を付ける。

```diff
-system.stateVersion = "25.05";
+system.stateVersion = lib.mkDefault "25.05";
```

**注意**: これは利用者の環境に影響し得る変更です。
既に `"25.05"` を書いている人には影響しませんが、
`mkDefault` にすると「hydenix 側の値」ではなく「利用者側の値」が勝つようになります。
挙動としては正しい方向ですが、上流には理由を添えて出したほうがよいでしょう。

### B-5. `hyde-diff-upstream` の `sha256` が固定されている

```nix
rev = "master";
sha256 = "sha256-cNOryXKFpVSTiAuzD0VQAV+2GQhJTTs1HBM6Z0cZoFo=";
```

`master` は動く標的なので、上流が進むと必ずハッシュ不一致で失敗します。

**直し方の選択肢**:

1. `sha256 = lib.fakeSha256;` にして「毎回エラーメッセージから正しい値を取る」運用にする
2. CI（renovate）でこのハッシュも自動更新の対象にする
3. `--impure` 前提のスクリプトに書き換え、Nix の外で `git clone` する

2 が実用的ですが、renovate の設定が複雑になります。
現状は「使うときに手で更新する」で運用できているので、優先度は低めです。

---

## C. 優先度: 低（仕様として割り切れるもの）

| 項目 | 内容 | 対応の方向性 |
|---|---|---|
| **`pyprland` が使えない** | 本家 issue #188（`hyde-shell pypr console` が動かない）が未解決。フォークでは imports もオプションも削除済み | 上流の HyDE 側の問題。scratchpad が欲しくなったら再検討 |
| **`nix`/`sddm`/`system` が `enable` に従わない** | `default = true` 固定（[07-5](./07-reading-notes.md)） | `config.hydenix.enable` に揃えるべきだが、既存利用者の環境が変わるので慎重に |
| **`cfg.vim or cfg.neovim`** | `or` は論理和ではない（[07-2](./07-reading-notes.md)） | `||` に直す。1 文字だが挙動が変わるので単独 PR に |
| **履歴の環境変数が `xdg.nix` にある** | 本家 issue #154 | `shell.nix` へ移す。一貫性の問題のみ |
| **fish の `$aurhelper` エイリアス** | Arch の名残で NixOS では動かない | 削除するか NixOS 版に置換 |
| **`.config/waybar/modules` を配置している** | 本家 TODO の「もう配置不要では」が残存 | 実機で外して試さないと判断できない |
| **hyprlock が `hyprland/` の外にある** | `lockscreen.nix` のまま。hyprlock と swaylock の排他 assertion も無い | 設計上の課題。統合するなら大きめの変更 |
| **`hyde config.toml` がオプション化されていない** | mutable なので手で編集するしかない | Nix オプション化は大仕事。効果も限定的 |
| **`kdePackages.kconfig` の要否** | コード中に TODO が残っている | 外して動くか実機で確認するだけ |
| **GTK テーマ初回変更時のちらつき** | `gtk.nix` に TODO | 原因不明。優先度低 |
| **spicetify 対応** | `spotify.nix` に TODO | flatpak 前提の案が書かれているだけ |
| **本家 issue #182: hypr windowrules errors** | 状態不明。HyDE の bump で解消した可能性あり | まず再現するか確認 |

---

## D. dotnix 側で持てばよいもの

hydenix に無くても、利用側（`santamn/dotnix`）で解決できるものです。
**上流に出す必要はありません。**

| 項目 | 対応 |
|---|---|
| `nh` によるガベージコレクト | dotnix の `modules/nixos/nix.nix` で持つ |
| nixos-anywhere / disko 対応 | dotnix 側で導入する |
| 多ホスト構成 | dotnix の `mkHost` / `hosts/` で対応済み。hydenix と両立する |

---

## E. すでに解決済み（本家 → フォークで直ったもの）

同じ問題を再度報告しないための記録です。

| 項目 | フォークでの状態 |
|---|---|
| nixpkgs / home-manager / Hyprland / HyDE の陳腐化 | ✅ 全て追従（renovate + workflow で自動化） |
| 本家 issue #169: `programs.git.settings.user.email` の型エラー | ✅ `git.nix` をモジュールごと削除 |
| 行番号決め打ちの `sed`（HyDE 更新で誤爆する） | ✅ コメントアウト |
| standalone home-manager 対応 | ✅ `homeConfigurations.default` を追加 |
| `nixosOptionsDoc` によるドキュメント生成 | ✅ mdbook + options ページ（GitHub Pages） |
| overlay の名前空間ネスト解消 | ✅ `pkgs/` へ再編 |
| demo VM | ✅ `demo/` を追加 |
| バイナリキャッシュ | △ `nixConfig` に hyprland cachix を追加（部分的） |
| hyprland モジュールの重複 | ✅ `mkHyprConfig` で一本化 |
| 必須アサーション（hostname 等） | ✅ 既定値 + `mkDefault` に変更 |
