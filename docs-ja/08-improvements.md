# 08. 将来加えると良い変更

直したほうがよいと判断した箇所の一覧です。上のものほど優先度が高く、下にいくほど仕様として割り切れるものになります。各項目は問題・原因・確認方法・修正方法の順に並べ、必要に応じて実害やリスクの節を挟んでいます。指摘を鵜呑みにせず、まず手元で実行して再現してみてください。

---

## 確認方法の共通手順

確認には 2 種類あります。

| 種類 | 内容 |
|-----|------|
| `grep` で足りるもの | コードの形を見れば分かる（書き間違い・書き漏らし） |
| `nix eval` が要るもの | 実際に評価するとどうなるかを見る必要がある |

`nix eval` を使う項目はリポジトリのルートで実行してください。`/etc/nix/nix.conf` に `experimental-features = nix-command flakes` が入っている前提です（hydenix / NixOS 環境では既定で有効。無ければ `--extra-experimental-features 'nix-command flakes'` を足す）。

ほとんどの確認は flake の `homeConfigurations.default` を評価するだけで、ビルドもアクティベーションも走りません。初回は依存 flake の取得で数分かかりますが、2 回目以降は数秒です。

以降の例は共通してこの形をとります。

```bash
nix eval --impure --expr '
  let hc = (builtins.getFlake (toString ./.)).homeConfigurations.default;
  in <調べたいもの>
'
```

- `--impure` は `builtins.getFlake` を使うために必要
- `toString ./.` はカレントディレクトリの絶対パスになる
- git に未追加（untracked）のファイルは flake から見えないので、新しいファイルを足して確認するときは先に `git add` すること
- 式の中に `foldl'` のようなアポストロフィが含まれる場合、シェルのシングルクォートを一度閉じる必要がある（`builtins.foldl'"'"'` のように書くか、式をファイルに書いて `nix eval --impure --file` を使う）

設定をいじったらどうなるかを試したいときは `extendModules` を使います。`configuration.nix` を書き換えずに済むので、確認用途にはこちらが便利です。

```bash
nix eval --impure --expr '
  let hc = (builtins.getFlake (toString ./.)).homeConfigurations.default;
      probe = hc.extendModules { modules = [{ <試したい設定> }]; };
  in <probe.config.… を調べる>
'
```

---

## A. 優先度: 高

### A-0. `pkgs/hyde` の rev を上げると素材アーカイブが無くてビルドが落ちる

#### 問題

HyDE 本家が 2026-07-27 のリリースコミット `b8cc647`（chore: Release - rc → master #1731）で `Source/arcs/` から `Code_Wallbash.vsix` と `Font_*.tar.gz` 6 個、それに `Cursor_BibataIce.tar.gz` を削除しました。ピン留め中の `v26.7.4` にはまだ残っているので現状は動きますが、これより後へ rev を上げた瞬間に [`pkgs/hyde/default.nix`](../pkgs/hyde/default.nix) の `buildPhase` が壊れます。

| 処理 | 削除後の挙動 |
|---|---|
| `unzip ./Source/arcs/Code_Wallbash.vsix` | ファイルが無く `unzip` が失敗してビルドが落ちる |
| `for fontarchive in ./Source/arcs/Font_*.tar.gz` | `if [ -f "$fontarchive" ]` に守られているためエラーにならず、**フォントが 0 個の hyde が黙って出来上がる** |

前者はすぐ気づけますが、後者は気づけません。上流追従を再開するなら、先にこの 2 つの入手先を決める必要があります。

#### 確認方法

ネットワークだけで確認できます。

```bash
for ref in v26.7.4 master; do
  echo "--- $ref ---"
  gh api "repos/HyDE-Project/HyDE/contents/Source/arcs?ref=$ref" --jq '.[].name'
done
# v26.7.4 側にだけ Code_Wallbash.vsix / Cursor_BibataIce.tar.gz / Font_*.tar.gz がある
```

`buildPhase` 側の扱いは `grep` で分かります。

```bash
grep -n 'Code_Wallbash\|Font_\*' pkgs/hyde/default.nix
```

#### 修正方法

`Code_Wallbash.vsix` は VS Code の wallbash 拡張なので、[`modules/hm/editors.nix`](../modules/hm/editors.nix) が参照している側ごと見直すか、拡張の配布元（`prasanthrangan/wallbash` 系リポジトリ）から `fetchFromGitHub` で取り直すことになります。フォントは nixpkgs に同等のもの（`nerd-fonts.*` / `noto-fonts-cjk-sans` / `maple-mono` など）が揃っているので、そちらへ寄せるのが素直です。

いずれにせよ、まず `if [ -f ... ]` の握りつぶしをやめて **無いなら落ちる** ようにしてください。フォントが 0 個であることに気づけないのが一番まずい状態です。

#### 対応済みの部分

この項目のうち、可変ブランチ ref から素材を取得していた問題と、CI がそれを検知できない問題は解決済みです。

- `pkgs/Bibata-Modern-Ice.nix` と `pkgs/Tela-circle-dracula.nix` は `raw/refs/heads/...` の `fetchurl` をやめ、nixpkgs の `bibata-cursors` / `tela-circle-icon-theme` からビルドするようになりました（[#3](https://github.com/santamn/hydenix/pull/3)）。前者は nixpkgs が XCursor 形式しか作らないため、`hyprcursor-util` で hyprcursor 版を作り直しています（理由は [#4](https://github.com/santamn/hydenix/pull/4) でコメントとして残してあります）
- `checks.${system}` に `hyde` / `Bibata-Modern-Ice` / `Tela-circle-dracula` と `theme-assets` が入り、素材パッケージが CI で実際にビルドされるようになりました（[#3](https://github.com/santamn/hydenix/pull/3) / [#5](https://github.com/santamn/hydenix/pull/5)）
- `flake-check.yml` に `schedule`（毎週月曜 03:00 UTC）が入り、PR の無い期間でも上流のファイル削除に気づけるようになりました
- 上流の PR #98 が入ったことで `.github/renovate.json` の customManager が `fetchFromGitHub` の `rev` を `github-releases` として拾うようになり、HyDE のタグも renovate の監視対象になりました。つまり次のタグが出れば renovate が PR を作り、その PR の CI が上記の `unzip` 失敗で落ちます。壊れる場所が利用者の実機ではなく PR になったので、この項目は「気づけないまま壊れる」問題から「上げる前に片付ける宿題」に変わっています

```bash
nix eval --impure --expr '
  builtins.attrNames (builtins.getFlake (toString ./.)).checks.x86_64-linux'
# => [ "Bibata-Modern-Ice" "Tela-circle-dracula" "hyde" "hyde-config" "hyde-ipc" "hydectl" "hyprquery" "theme-assets" ]
```

### A-1. `mutableGeneration` — 存在しない依存名を参照している

#### 問題

3 つの activation script が、実在しないエントリを待っています。

| ファイル | エントリ名 |
|---|---|
| `modules/hm/theme.nix` | `home.activation.setTheme` |
| `modules/hm/hyde.nix` | `home.activation.createCavaConfig` |
| `modules/hm/hyprland/default.nix` | `home.activation.createHyprConfigs` |

該当箇所は次のコマンドで一覧できます。

```bash
grep -rn 'entryAfter \["mutableGeneration"\]' modules/
```

いずれも `lib.hm.dag.entryAfter ["mutableGeneration"]` と書かれていますが、`modules/hm/mutable.nix` が実際に定義しているのは `mutableFileGeneration` です。

#### 原因

home-manager の DAG は存在しない依存名を黙って無視します。エラーにならないため誰も気づきませんが、mutable ファイルのコピー後に実行するという意図した順序制約が一切効いていません。実行位置は toposort の実装依存で決まっており、home-manager の更新で順番が変わり得ます。

#### 実害

`setTheme` が、mutable なスクリプト本体（`~/.local/lib/hyde/theme.switch.sh`）のコピー完了前に走る可能性があります。現状は `writeBoundary` などの他の制約で結果的に順序が保たれている可能性が高く、これが原因で壊れているという確証はありません。潜在的な問題という位置づけです。

#### 確認方法

依存先として書かれている名前と、実在するエントリ名を突き合わせます。

```bash
nix eval --impure --expr '
  let hc = (builtins.getFlake (toString ./.)).homeConfigurations.default;
      acts = hc.config.home.activation;
  in {
    setThemeAfter         = acts.setTheme.after;
    createCavaConfigAfter = acts.createCavaConfig.after;
    存在する_mutableGeneration     = builtins.hasAttr "mutableGeneration" acts;
    存在する_mutableFileGeneration = builtins.hasAttr "mutableFileGeneration" acts;
  }'
```

実行結果:

```
{ createCavaConfigAfter = [ "mutableGeneration" ];
  setThemeAfter = [ "mutableGeneration" ];
  存在する_mutableFileGeneration = true;
  存在する_mutableGeneration = false; }
```

`after` が指している `mutableGeneration` が `false`（実在しない）である一方、実際のエントリは `mutableFileGeneration` として存在しています。それでもエラーにならず評価が通っていることが、DAG が存在しない依存名を黙って無視することの証拠です。

#### 修正方法

3 か所の文字列を変えるだけです。

```diff
-home.activation.setTheme = lib.hm.dag.entryAfter ["mutableGeneration"] ''
+home.activation.setTheme = lib.hm.dag.entryAfter ["mutableFileGeneration"] ''
```

リスクはありません。`mutable.nix` の `config` は `enable` フラグで囲われていない（無条件）ので、このエントリは常に存在します。依存先が消えることはありません。

> この修正は上流へ PR を送る価値があります。手順は [09-fork-workflow.md](./09-fork-workflow.md) を参照。

### A-2. activation script が `$DRY_RUN_CMD` を使っていない

#### 問題

A-1 と同じ 3 つのスクリプトが、`mkdir` / `touch` / `chmod` や `theme.switch.sh` の実行を生のコマンドで書いています。

```nix
home.activation.createCavaConfig = lib.hm.dag.entryAfter [...] ''
  mkdir -p "$HOME/.config/cava"      # ← $DRY_RUN_CMD が無い
  touch "$HOME/.config/cava/config"
  chmod 644 "$HOME/.config/cava/config"
'';
```

#### 原因

home-manager は `$DRY_RUN_CMD` という変数を用意しており、`--dry-run` 相当のときは `echo` に、通常時は空文字になります。これを付けずに書いたコマンドは、dry-activate でも実際に実行されます。`mutable.nix` は正しく `$DRY_RUN_CMD` を使っているので、対比すると分かりやすいです。

#### 実害

`nixos-rebuild dry-activate` が副作用を持ちます。テーマ適用まで走るので、確認のつもりが本番適用になります。

#### 確認方法

生成された activation script を直接読みます。

```bash
nix eval --raw --impure --expr '
  (builtins.getFlake (toString ./.)).homeConfigurations.default
    .config.home.activation.createCavaConfig.data
'
```

実行結果:

```
mkdir -p "$HOME/.config/cava"
touch "$HOME/.config/cava/config"
chmod 644 "$HOME/.config/cava/config"
```

`$DRY_RUN_CMD` が 1 つも付いていないことが確認できます。`createCavaConfig` の部分を `setTheme` / `createHyprConfigs` に変えれば他の 2 つも同様に見られます。対比のため `mutableFileGeneration` も同じ方法で表示すると、そちらには `$DRY_RUN_CMD cp ...` と付いているのが分かります。

#### 修正方法

```diff
-  mkdir -p "$HOME/.config/cava"
+  $DRY_RUN_CMD mkdir -p "$HOME/.config/cava"
```

> [!IMPORTANT]
> A-1 とは別の PR にしてください。最初の PR は小さく保つのが通りやすさの鉄則です。A-1 は文字列 3 か所でリスクゼロ、A-2 は挙動の変更を含むため議論が要ります。

### A-3. `mutable` ファイルが設定から消しても残る

#### 問題

`mutable = true` のファイルはコピーなので home-manager の管理外です。設定から外してもホームに残り続け、手動削除が必要です。

#### 原因

これは仕組み上の必然です（[04](./04-mutable-files.md) 参照）。ただし実運用でいちばん効く問題でもあります。特にフォークでは `mkHyprConfig` の生成物がすべて mutable になったため、影響範囲が本家より広がっています。

#### 確認方法 1（影響範囲を数える）

mutable なファイルの一覧を出します。

```bash
nix eval --impure --expr '
  let hc = (builtins.getFlake (toString ./.)).homeConfigurations.default;
      mut = builtins.filter (f: f.mutable or false) (builtins.attrValues hc.config.home.file);
  in { count = builtins.length mut; targets = builtins.map (f: f.target) mut; }'
```

執筆時点で 115 件でした。これがすべて、設定から消しても残るファイルです。`grep -rn "mutable = true" modules/ | wc -l` は宣言の数（60）なので、`mkHyprConfig` などのループで増える分は数えられません。実数を見るには上の方法が必要です。

#### 確認方法 2（実機で残留を見る）

mutable ファイルはシンボリックリンクではなく実ファイルです。

```bash
# リンクなら "-> /nix/store/..." が出る。実ファイルならパスだけが出る
ls -l ~/.config/kitty/theme.conf ~/.config/hypr/keybindings.conf

# home-manager 管理下の実ファイル（mutable なもの）を一覧する
find ~/.config/hypr ~/.config/waybar -maxdepth 1 -type f
```

残留そのものを再現するなら、`mutable = true` のモジュールを 1 つ無効にして `nixos-rebuild switch` した後、該当ファイルがまだ存在することを確認します。

#### 当面の対処

おかしくなったらリセットします。

```bash
rm -rf ~/.config/hyde ~/.local/share/hyde ~/.cache/hyde
# その後 nixos-rebuild switch で再配置される
```

#### 修正方法（未実装・本家 TODO）

- `mutable.enable` … 機能そのものを切れるようにする
- `mutable.mode` … `initOnly`（初回だけコピー）と `replace`（毎回上書き）を選べるようにする
- 前世代の mutable ファイル一覧を記録し、設定から消えたものを自動削除する
- generation ロールバック時に mutable ファイルも戻す

3 つ目が本命ですが、ユーザーが手で編集した内容を消してよいかの判断が難しく、設計上の議論が必要です。大きめの変更なので、上流に投げる前に issue で相談するのが無難です。

### A-4. `mutable` オプションが `xdg.configFile` に生えていない

#### 問題

`modules/hm/mutable.nix` は `home.file` / `xdg.configFile` / `xdg.dataFile` の 3 つに `mutable` を追加しているつもりですが、実際に生えるのは 2 つです。`xdg.configFile.<name>.mutable` は存在しません。

該当箇所は [`modules/hm/mutable.nix`](../modules/hm/mutable.nix) の `options` ブロック末尾です。

```nix
mergeAttrsList = builtins.foldl' lib.mergeAttrs {};   # ← ここ
...
mergeAttrsList (
  map (attrPath: lib.setAttrByPath attrPath (lib.mkOption {type = fileAttrsType;})) fileOptionAttrPaths
)
```

#### 原因

`lib.mergeAttrs` の実体は `x: y: x // y` で、トップレベルのキーしか見ない浅いマージです。`map` が作るのは次の 3 つの属性集合ですが、

```nix
[ { home = { file       = OPT; }; }
  { xdg  = { configFile = OPT; }; }
  { xdg  = { dataFile   = OPT; }; } ]
```

`//` で畳み込むと `xdg` というキーが丸ごと後勝ちで置き換わります。

```nix
{}
// { home = {file = OPT;}; }        # => { home = {file = OPT;}; }
// { xdg  = {configFile = OPT;}; }  # => { home = …; xdg = {configFile = OPT;}; }
// { xdg  = {dataFile = OPT;}; }    # => { home = …; xdg = {dataFile   = OPT;}; }
                                    #                      ↑ configFile が消える
```

`fileOptionAttrPaths` の 3 要素のうち、先頭 2 階層が衝突する `xdg.*` の 2 つで後ろだけが残る、という形です。`home.file` と `xdg.dataFile` は無事で、`xdg.configFile` だけが落ちます。

なお `config` 側は `file.mutable or false` と `or` でフォールバックしているため、オプションが無くても評価は通ります。エラーも警告も出ません。

#### 実害

現時点ではありません。hydenix 内の `mutable = true` はすべて `home.file` 経由で書かれており、`xdg.configFile` / `xdg.dataFile` はこのリポジトリのどこからも使われていないためです。

```bash
grep -rn "xdg.configFile\|xdg.dataFile" modules/   # コメント行しかヒットしない
```

ただし利用者が `xdg.configFile."foo".mutable = true;` と書くと、モジュールシステムがそんなオプションは無いというエラーで落ちます。[04-mutable-files.md](./04-mutable-files.md) の記述とも食い違うため、潜在バグとして直しておく価値があります。

#### 確認方法 1（最小再現）

hydenix を評価せず、`lib` の挙動だけを見ます。数秒で終わります。

```bash
nix eval --impure --expr '
  let lib = (builtins.getFlake "nixpkgs").lib;
      paths = [["home" "file"] ["xdg" "configFile"] ["xdg" "dataFile"]];
  in builtins.attrNames
       (builtins.foldl'"'"' lib.mergeAttrs {} (map (p: lib.setAttrByPath p "OPT") paths)).xdg
'
# => [ "dataFile" ]        configFile が消えていれば再現
```

`builtins.getFlake "nixpkgs"` は flake レジストリ経由で nixpkgs を引くので、hydenix の `flake.lock` とは無関係に単体で走ります。

`lib.mergeAttrs` を `lib.recursiveUpdate` に替えるだけで直ることも、同じ式で確認できます。

```bash
nix eval --impure --expr '
  let lib = (builtins.getFlake "nixpkgs").lib;
      paths = [["home" "file"] ["xdg" "configFile"] ["xdg" "dataFile"]];
  in builtins.attrNames
       (builtins.foldl'"'"' lib.recursiveUpdate {} (map (p: lib.setAttrByPath p "OPT") paths)).xdg
'
# => [ "configFile" "dataFile" ]     両方残る
```

#### 確認方法 2（実際のモジュールで確認）

3 つのオプションの submodule に `mutable` が居るかどうかを直接調べます。

```bash
nix eval --impure --expr '
  let hc = (builtins.getFlake (toString ./.)).homeConfigurations.default;
      has = o: builtins.hasAttr "mutable" (o.type.getSubOptions []);
  in {
    "home.file"      = has hc.options.home.file;
    "xdg.configFile" = has hc.options.xdg.configFile;
    "xdg.dataFile"   = has hc.options.xdg.dataFile;
  }'
```

実行結果:

```
{ "home.file" = true; "xdg.configFile" = false; "xdg.dataFile" = true; }
```

`xdg.configFile` だけが `false` になっていれば再現しています。

#### 修正方法

畳み込みの関数を深いマージに替えるだけです。

```diff
-    mergeAttrsList = builtins.foldl' lib.mergeAttrs {};
+    mergeAttrsList = builtins.foldl' lib.recursiveUpdate {};
```

`lib.mkMerge` を使って `options = lib.mkMerge (map ... )` とする手もありますが、`recursiveUpdate` のほうが変更が 1 行で済みます。

#### リスク

低いです。`xdg.configFile` にオプションが増えるだけで、既存の挙動は変わりません（誰も使っていないため）。ただし `home.file` と `xdg.configFile` の両方に同じパスを書いている設定があると、これまで無視されていた `mutable` が効き始める可能性はあります。修正後に確認方法 2 が 3 つとも `true` になることを確かめてください。

> この修正も上流へ PR を送る価値があります。A-1 と同様、小さく独立した変更です。

---

## B. 優先度: 中

### B-1. `hydectl` の `mainProgram` が間違っている

#### 問題

```nix
# pkgs/hydectl/default.nix
meta = with lib; {
  ...
  mainProgram = "hyde-ipc";   # ← 正しくは "hydectl"
};
```

`pkgs/hyde-ipc/default.nix` からのコピペと思われます。

#### 実害

`nix run .#hydectl` が `hydectl` ではなく `hyde-ipc` を起動しようとします（`$out/bin/hyde-ipc` は存在しないのでエラーになります）。

#### 確認方法

メタ情報を直接読みます。ビルドは走りません。

```bash
nix eval --impure --expr '
  (builtins.getFlake (toString ./.)).packages.x86_64-linux.hydectl.meta.mainProgram
'
# => "hyde-ipc"     "hydectl" ならば修正済み
```

darwin 上でも `x86_64-linux` の評価はできます（ビルドはできません）。

#### 修正方法

`mainProgram = "hydectl";` に変更します。1 行で済むので PR 向きの小さな修正です。

### B-2. `hyde-gallery` の `sha256` が空

#### 問題

```nix
# pkgs/hyde-gallery/default.nix
sha256 = "";
```

#### 実害

このパッケージはビルドできません。overlay には `hyde-gallery` として登録され、`flake.nix` の `packages` にも `inherit (pkgs) ... hyde-gallery;` として入っているので、`nix build .#hyde-gallery` は失敗します。日常的に参照されないため表面化していないだけです。

#### 確認方法

`sha256 = ""` は全ゼロのハッシュに正規化されます。これは実在しないハッシュなので、fetch は必ず不一致で失敗します。

```bash
nix eval --impure --expr '
  (builtins.getFlake (toString ./.)).packages.x86_64-linux.hyde-gallery.src.outputHash
'
# => "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="   全ゼロなら再現
```

#### 修正方法

選択肢は 2 つです。

1. 正しい `sha256` を入れる（`nix-prefetch-git` で取得）
2. 使っていないので削除する

実際のテーマは `pkgs/hydenix-themes/` 以下で個別に取得しており、`hyde-gallery` を参照しているコードは 1 つもありません。2 が妥当だと思います。

### B-3. `assertions.nix` が `hyprsunset` を検証していない

#### 問題

フォークで `hyprsunset` を追加したときに、`assertions.nix` の 2 つのリスト（`activeOverrides` と `assertions`）への追加が漏れています。

#### 実害

`hyprsunset.overrideConfig = "";`（空文字）を書いても弾かれず、override 使用中の警告も出ません。

#### 確認方法

検証されている `keybindings` と並べて、両方に空文字を与えます。片方しか怒られないなら再現です。

```bash
nix eval --impure --expr '
  let hc = (builtins.getFlake (toString ./.)).homeConfigurations.default;
      probe = hc.extendModules { modules = [{
        hydenix.hm.hyprland.hyprsunset.overrideConfig = "";
        hydenix.hm.hyprland.keybindings.overrideConfig = "";
      }]; };
  in probe.config.home.file'
```

実行結果（エラー終了しますが、それが期待どおりです）:

```
error:
Failed assertions:
- hydenix.hm.hyprland.keybindings.overrideConfig is set but empty. …
```

`keybindings` は報告されるのに `hyprsunset` は 1 行も出てきません。修正後は 2 件とも列挙されるようになります。`grep -n "overrideConfig" modules/hm/hyprland/assertions.nix` でも、`hyprsunset` だけが 2 つのリストに載っていないことが確認できます。

#### 修正方法

他の 5 つと同じ行を 2 か所に足すだけです。

```nix
(lib.optionalString (cfg.hyprsunset.overrideConfig != null) "hyprsunset.overrideConfig")
```

```nix
{
  assertion = cfg.hyprsunset.overrideConfig == null || cfg.hyprsunset.overrideConfig != "";
  message = "hydenix.hm.hyprland.hyprsunset.overrideConfig is set but empty. ...";
}
```

より良い直し方として、`mkHyprConfig` を使っている以上、assertion も `mkHyprConfig` 側で生成すべきです。そうすればモジュール追加時の漏れが構造的に無くなります。こちらのほうが PR としては筋が良いですが、変更範囲は大きくなります。

### B-4. `stateVersion` に `mkDefault` が無い

#### 問題

```nix
# modules/system/default.nix
system.stateVersion = "25.05";

# modules/hm/default.nix
home.stateVersion = "25.05";
```

#### 原因

利用者側も自分の `configuration.nix` / `home.nix` で `stateVersion` を書くのが普通です。型のマージが `mergeEqualOption`（値が全て等しければ通る）なので、両方が `"25.05"` である限りエラーになりません。しかし片方でも変えた瞬間に定義衝突でビルドが落ちます。

そもそも `stateVersion` は利用者がいつ環境を作ったかを表す値なので、ライブラリ側が固定値を主張するのは筋が悪いです。

#### 確認方法

オプション定義の優先度を見ます。`mkDefault` が付いていれば `1000`、素の代入なら `100` になります。

```bash
nix eval --impure --expr '
  (builtins.getFlake (toString ./.)).homeConfigurations.default
    .options.home.stateVersion.highestPrio
'
# => 100      素の代入（mkDefault 済みなら 1000）
```

衝突そのものを再現するなら、別の値を重ねてみます。

```bash
nix eval --impure --expr '
  let hc = (builtins.getFlake (toString ./.)).homeConfigurations.default;
      probe = hc.extendModules { modules = [{ home.stateVersion = "24.11"; }]; };
  in probe.config.home.stateVersion'
```

```
error: The option `home.stateVersion' has conflicting definition values:
- In `<unknown-file>': "25.05"
- In `<unknown-file>': "24.11"
```

`mkDefault` を付けた後は、これが `"24.11"`（利用者側の値）を返すようになります。

#### 修正方法

`lib.mkDefault` を付けます。

```diff
-system.stateVersion = "25.05";
+system.stateVersion = lib.mkDefault "25.05";
```

これは利用者の環境に影響し得る変更です。既に `"25.05"` を書いている人には影響しませんが、`mkDefault` にすると hydenix 側の値ではなく利用者側の値が勝つようになります。挙動としては正しい方向ですが、上流には理由を添えて出したほうがよいでしょう。

### B-5. `hyde-diff-upstream` の `sha256` が固定されている

#### 問題

```nix
rev = "master";
sha256 = "sha256-cNOryXKFpVSTiAuzD0VQAV+2GQhJTTs1HBM6Z0cZoFo=";
```

`master` は動く標的なので、上流が進むと必ずハッシュ不一致で失敗します。

#### 確認方法

`grep -n "rev\|sha256" pkgs/hyde-diff-upstream/default.nix` で `rev = "master"` と固定ハッシュが同居していることを見るのが手っ取り早いです。

実際に破綻しているかどうかは、上流の現在の `master` と記録されたハッシュを突き合わせるしかありません（ネットワークアクセスが要ります）。

```bash
nix-prefetch-git --quiet https://github.com/HyDE-Project/HyDE master | grep hash
# 出力が pkgs/hyde-diff-upstream/default.nix の sha256 と違えば、既に失敗する状態
```

#### 修正方法

選択肢は 3 つです。

1. `sha256 = lib.fakeSha256;` にして、毎回エラーメッセージから正しい値を取る運用にする
2. CI（renovate）でこのハッシュも自動更新の対象にする
3. `--impure` 前提のスクリプトに書き換え、Nix の外で `git clone` する

2 が実用的ですが、renovate の設定が複雑になります。現状は使うときに手で更新するで運用できているので、優先度は低めです。

### B-6. `cfg.vim or cfg.neovim` — `or` が論理和として書かれている

#### 問題

```nix
# modules/hm/editors.nix
(lib.mkIf (cfg.vim or cfg.neovim) {
  ".config/vim/colors/wallbash.vim" = {...};
  ".config/vim/hyde.vim" = {...};
  ".config/vim/vimrc" = {...};
})
```

`vim = false; neovim = true;` にしても、この `mkIf` は `false` になります。配置されるはずの `.config/vim/` 一式（wallbash 配色・vimrc）が置かれません。

#### 原因

Nix の `or` は属性が存在しないときの既定値を与える演算子で、判定するのは値の真偽ではなくキーの有無です。

```nix
{a = false;}.a or true   # => false （a は存在するので、その値がそのまま返る）
{}.a or true             # => true  （a が無いので既定値）
```

`cfg.vim` は `options` ブロックで `default = true` 付きで宣言されているため、モジュール評価の時点で必ず存在します。よって `cfg.vim or cfg.neovim` はどう設定しても `cfg.vim` と等価で、`cfg.neovim` は一度も参照されません。

Python / Lua / Ruby の `a or b`（a が偽なら b）と同じ語感で書くと、Nix では静かに意味が変わります。`cfg.vim` は属性選択式なので、構文エラーにも型エラーにもならず評価が通ってしまうのが厄介な点です。

#### 確認方法

`vim = false; neovim = true;` にして、配置されるはずの `.config/vim/vimrc` が居るかを見ます。

```bash
nix eval --impure --expr '
  let hc = (builtins.getFlake (toString ./.)).homeConfigurations.default;
      probe = hc.extendModules { modules = [{
        hydenix.hm.editors.vim = false;
        hydenix.hm.editors.neovim = true;
      }]; };
  in builtins.hasAttr ".config/vim/vimrc" probe.config.home.file'
# => false     配置されていない。修正後は true になる
```

`vim = true` に戻すと `true` が返ります。`neovim` の値を何に変えても結果が動かないことも、同じ方法で確かめられます。

#### 修正方法

```diff
-(lib.mkIf (cfg.vim or cfg.neovim) {
+(lib.mkIf (cfg.vim || cfg.neovim) {
```

配置対象は vim / neovim のどちらからも使える `.config/vim/` 配下のファイルなので、どちらか一方でも有効なら配置するという元の設計意図は妥当です。演算子の選択だけが誤っている状態で、意図を変える変更ではありません。

#### PR の出し方

1 文字の変更ですが挙動が変わるので、他の修正と混ぜず単独 PR にします。`or` は attribute fallback であって論理和ではない、という説明を本文に添えてください。既定値が両方 `true` のため、既存利用者のうち `vim = false` を明示している人だけに影響します。

### B-7. テーマ自動更新が一度も動いていない

#### 問題

[`scripts/update-themes.sh`](../scripts/update-themes.sh) と [`update-themes.yml`](../.github/workflows/update-themes.yml) は、テーマの `rev` / `sha256` を定期更新するための仕組みですが、実際には `rev` も `sha256` も一度も更新されていません。毎日 0:00 UTC に起動して、差分ゼロで PR を作らずに終わっています。

#### 原因

スクリプト冒頭の分岐が原因です。

```bash
# scripts/update-themes.sh:28-31
if [[ "$CURRENT_REV" =~ ^[0-9a-f]{40}$ ]]; then
  LATEST_COMMIT_HASH="$CURRENT_REV"     # ← 最新 ＝ 今の値 と決めつけている
```

`rev` がコミットハッシュなら最新コミットは今のコミットだとみなし、以降は `sha256` を再検証するだけの分岐に入ります。しかし同じコミットのアーカイブは当然同じハッシュになるので、この検証は必ず一致し、必ず `already up to date` で終わります。

そして `pkgs/hydenix-themes/` のテーマ 58 ファイルが、例外なく 40 桁のコミットハッシュで固定されています。つまり、

- ブランチ名を解決する `else` 側（L32-42）には永久に到達しない
- `rev` を書き換える `sed`（L76）も永久に実行されない

おそらく初回実行時にブランチ名からコミットハッシュへの置換が一度だけ走り、それ以降は自分で自分を凍結してしまった、という自己無効化のパターンです。

#### 実害

テーマが upstream に追従しません。壁紙の追加や `.dcol` の修正が反映されないだけなので破壊的ではありませんが、自動更新されているつもりで放置されるぶん質が悪いです。

#### 確認方法 1（pin がすべてハッシュであること）

```bash
grep -o 'rev = "[^"]*"' pkgs/hydenix-themes/*.nix | grep -cv '[0-9a-f]\{40\}'
# => 0     ブランチ名で pin されたファイルが 1 つも無い＝else 側に入らない
```

#### 確認方法 2（一度も自動コミットされていないこと）

```bash
git log --all --oneline --grep="chore(themes)"
# => e561f90 chore(themes): `Ice-Age`: bump hash
```

workflow が付けるはずの `chore(themes): automated theme updates` は履歴に 1 件も存在しません。唯一のハッシュ更新は人間による手動コミットです。

#### 確認方法 3（実際の陳腐化を数える）

`git ls-remote` で追跡先の HEAD と突き合わせます。ネットワークアクセスが要りますが、clone はしないので 1〜2 分で終わります。

```bash
for f in pkgs/hydenix-themes/*.nix; do
  case "$f" in */default.nix) continue;; esac
  n=$(basename "$f" .nix)
  rev=$(grep -o 'rev = "[^"]*"' "$f" | cut -d'"' -f2)
  url=$(grep -o 'homepage = "[^"]*"' "$f" | cut -d'"' -f2)
  case "$url" in
    */tree/*) repo="${url%/tree/*}"; ref="refs/heads/${url##*/tree/}";;
    *)        repo="$url"; ref="HEAD";;
  esac
  head=$(git ls-remote "$repo" "$ref" 2>/dev/null | awk '{print $1}')
  [ "$rev" = "$head" ] || echo "$n: ${rev:0:8} -> ${head:0:8}"
done
```

2026-07 時点の結果は 58 件中 11 件が upstream に遅れていました。

```
1-Bit: ee6a1336 -> 84b2f94e            Moonlight:       cc389fdc -> 50f77a6e
Breezy-Autumn: db980839 -> 959294bf    Obsidian-Purple: d1c90091 -> b73f00b1
Cosmic-Blue: f5e0e85d -> ad8a9a50      Peace-Of-Mind:   45ee6f24 -> 632fb4a0
Crimson-Blue: 5bc78a51 -> ee6da6ff     Timeless-Dream:  8a10d655 -> 5104d77c
Electra: 61cd9718 -> 953676ce          Monterey-Frost:  4675ddd4 -> 559edd92
Grukai: 95e0b926 -> 3945b4a1
```

このほかに `Red-Stone: 44c499a0 ->`（右辺が空）が 1 件出ますが、これはテーマが古いのではなく、上のスクリプトがブランチを特定できなかったケースです。homepage が `tree/Red-Stone` なのに実ブランチが `Red_Stone` のため、`refs/heads/Red-Stone` の問い合わせが空を返しています（実ブランチで引き直すと pin は最新と一致します）。homepage をブランチ名の情報源にできないことの実例なので、下の修正方法の根拠になります。

#### 修正方法

`rev` の形で分岐するのをやめるのが本質ですが、それだけでは直りません。追跡先の情報がどこにも保持されていないのが本当の欠落です。

テーマの配布元は 2 種類に分かれます。

| 形 | 追跡先 | 件数 |
|---|---|---|
| テーマ専用リポジトリ（`rishav12s/Rain-Dark` など） | デフォルトブランチ | 37 |
| 1 リポジトリをブランチで分割（`HyDE-Project/hyde-themes`、`hyde-gallery`、`mahaveergurjar/Theme-Gallery`、`RAprogramm/HyDe-Themes`） | 個別のブランチ | 21 |

後者のブランチ名は `meta.homepage` の `/tree/<ブランチ>` に事実上書かれているだけで、機械可読な形では持っていません。しかもその homepage が信用できないケースがあります。

- [`Red-Stone.nix`](../pkgs/hydenix-themes/Red-Stone.nix) → homepage は `tree/Red-Stone` だが、実ブランチは `Red_Stone`（アンダースコア）
- [`Mac-OS.nix`](../pkgs/hydenix-themes/Mac-OS.nix) → homepage は `tree/Mac-Os`（大文字小文字が不一致）

スクリプトが `NAME=$(basename "$NIX_FILE" .nix)` を計算しているのに `echo` 以外で使っていないのは、当初ファイル名イコールブランチ名を想定していた名残に見えますが、上記のとおりその前提も成り立ちません。

したがって修正は次の 2 段構えになります。

1. 各テーマファイルに追跡先を明示するフィールドを足す

   ```diff
    src = pkgs.fetchFromGitHub {
      owner = "mahaveergurjar";
      repo = "Theme-Gallery";
   +  ref = "Red_Stone";        # 専用リポジトリなら "main" / "master"
      rev = "44c499a0...";
   ```

   `ref` は `fetchFromGitHub` に渡さず、更新スクリプトだけが読むメタ情報として扱います（`mkTheme` 側で受け取って捨てるか、`src` の外に置く）。

2. スクリプトを、常に `git ls-remote <url> <ref>` で解決して、変われば `rev` と `sha256` の両方を書き換える形に直します。`rev` の形を見る分岐（L28-42）は丸ごと不要になります。

あわせて、workflow の PR 本文（`This PR updates the sha256 for HyDE themes based on their specified rev.`）と [05-theme-system.md](./05-theme-system.md) の「`sha256` は …… が定期的に更新します」という記述も実態に合わせる必要があります。

#### 付随して直すとよい点

- [`update-themes.sh`](../scripts/update-themes.sh) L13-16 の `grep -oP` は GNU grep 依存で、`nix-shell -p` の指定に GNU grep が入っていないため macOS ローカルでは動きません（CI の ubuntu では通るので表面化していない）。`sed -E` で代替するか `gnugrep` を足す
- L51 の `nix hash convert --hash-algo sha256` と L67 の `nix hash to-sri --type sha256` が不統一（出力はどちらも SRI なので実害は無い。`nix hash to-sri` は deprecated）

#### 優先度の補足

ビルドは壊れないので B に置いていますが、自動化が存在するのに機能していないという点では A 相当の危うさがあります。上流にもそのまま存在する問題なので、PR を送る価値があります。

### B-8. `setThemeDconf.service` が存在しないスクリプトを起動している

#### 問題

テーマ適用 3 段構えの 2 段目が、実在しないファイルを指しています。

```nix
# modules/hm/theme.nix:184
ExecStart = ''
  ${config.home.homeDirectory}/.local/lib/hyde/dconf.set.sh
'';
```

現在ピン留めしている HyDE に `dconf.set.sh` はありません。上流のリファクタリングで `color/dconf.sh` へ移動・改名されています。TODO 中の `theme.set.sh` も同様に消えています（`color.set.sh` が相当）。

#### 実害

見た目ほど大きくありません。dconf 設定自体は別経路で当たっています。`theme.switch.sh` の末尾が `wallpaper.sh` を呼び、`wallpaper/core.sh` が `color.set.sh` をバックグラウンド実行し、その `color.set.sh` が `load_dconf_kdeglobals()` の中で `color/dconf.sh` を source するためです。

つまり 2 段目は丸ごと死んでいるものの、3 段目が同じ仕事を内包しているので、結果として破綻していません。残るのは次の 2 点です。

- `systemctl --user --failed` に常時 1 件出る（セッションが degraded 扱いになる）
- `After = ["setThemeDconf.service"]` の順序制約が意味を失っている

#### 確認方法

ピン留め中の rev に対して 3 つのパスの有無を引きます。

```bash
REV=$(nix eval --impure --raw --expr '
  (builtins.getFlake (toString ./.)).packages.x86_64-linux.hyde.src.rev')

for f in dconf.set.sh theme.set.sh color/dconf.sh; do
  printf '%s  %s\n' \
    "$(curl -s -o /dev/null -w '%{http_code}' \
      "https://raw.githubusercontent.com/HyDE-Project/HyDE/$REV/Configs/.local/lib/hyde/$f")" "$f"
done
```

実行結果:

```
404  dconf.set.sh
404  theme.set.sh
200  color/dconf.sh
```

サービスが指しているパスも確認できます。

```bash
nix eval --impure --expr '
  (builtins.getFlake (toString ./.)).homeConfigurations.default
    .config.systemd.user.services.setThemeDconf.Service.ExecStart'
# => [ "/home/hydenix/.local/lib/hyde/dconf.set.sh\n" ]
```

実機なら次の 2 つが直接の証拠になります。

```bash
ls ~/.local/lib/hyde/dconf.set.sh              # No such file or directory
systemctl --user status setThemeDconf.service  # status=203/EXEC
```

#### 修正方法

サービスごと削除するのが妥当です。`setTheme.service` の `After` からも該当行を外します。

> [!WARNING]
> パスを `color/dconf.sh` に差し替えるだけでは直りません。このスクリプトは `color.set.sh` から source される前提で書かれており、単体起動では `dcol_mode` が未設定になります。先頭の `COLOR_SCHEME="prefer-$dcol_mode"` が `"prefer-"` という壊れた値になるため、かえって悪化します。`color.set.sh` を直接呼ぶ手もありますが、引数に現在の壁紙パスが要るため、サービス側でそれを解決する処理が新たに必要になります。

#### 優先度の補足

壊れて見えるわりに実害が小さいので B に置いています。根本的には HyDE のスクリプト名を Nix 側にハードコードしていることが原因で、これは C-1 で扱う設計課題そのものの実例です。

### B-9. fish の `$aurhelper` エイリアス 6 個は必ず失敗する

#### 問題

[`modules/hm/shell.nix`](../modules/hm/shell.nix) の `interactiveShellInit` に、Arch の AUR ヘルパー向けエイリアスが 6 個そのまま残っています。

```nix
# modules/hm/shell.nix:239-244
alias un='$aurhelper -Rns'
alias up='$aurhelper -Syu'
alias pl='$aurhelper -Qs'
alias pa='$aurhelper -Ss'
alias pc='$aurhelper -Sc'
alias po='$aurhelper -Qtdq | $aurhelper -Rns -'
```

#### 原因

理由が 2 段あります。

1 つ目は、上流 HyDE ではこの 6 行がコメントアウトされていることです。移植元の [`Configs/.config/fish/user.fish`](https://github.com/HyDE-Project/HyDE/blob/a51460a7b1a822ee7194318b60a38850f711b923/Configs/.config/fish/user.fish) L15-20 はすべて `#` 付きです。hydenix 側が `#` を外して書き写した形になっています。

2 つ目は、`$aurhelper` がプロンプトまで届かないことです。同じ `user.fish` の L41 に `set aurhelper yay`（コメント無し）があり、これは `shell.nix:197` で source されます。しかし home-manager の fish モジュールは `interactiveShellInit` を `status is-interactive; and begin … end` の中に埋め込みます（[home-manager `modules/programs/fish.nix`](https://github.com/nix-community/home-manager/blob/079a3b5d1aa6a719920a51316253b7d6dd22738d/modules/programs/fish.nix#L774-L785)）。fish の `set` はスコープ指定が無いとそのブロックのローカル変数を作るので、`end` を抜けた時点で消えます。hydenix 自身が `shell.nix:192` で `set -g fish_greeting` と `-g` を明示しているのと対照的です。

一方 `alias` が定義するのは関数で、関数はブロックに関係なく残ります。結果、エイリアスだけ残り、変数は消えるという状態になります。`un` を打つと `$aurhelper` が空展開され、`-Rns` をコマンドとして実行しようとして失敗します。

仮に変数が残っていたとしても値は `yay` で、NixOS に `yay` はありません。どちらに転んでも動きません。

> [!NOTE]
> 同じ理由で `user.fish` L38 の `set EDITOR code` も効いていません。こちらは効かないほうが望ましいので直す必要はありませんが、上の 2 番目の説明が正しいことの傍証になります。

#### 実害

小さいです。`hydenix.hm.shell.fish.enable` は既定 `false` なので、fish を明示的に有効にした利用者だけが踏みます。ただし `up` / `pl` のような短い名前を、動かないエイリアスが占有し続けるのは邪魔です。利用者が自分で `up` を定義しても hydenix 側の定義と衝突はしませんが（後勝ち）、`shellAliases` に書いた場合は HM が先に流すので hydenix 側が勝ちます。

#### 確認方法 1（grep）

zsh 側には同じエイリアスが無いこと、fish だけの問題であることを確認します。

```bash
grep -rn 'aurhelper' modules/
# => modules/hm/shell.nix の 7 行（コメント 1 + alias 定義 6）だけ
```

#### 確認方法 2（生成される fish 設定を見る）

fish は既定で無効なので `extendModules` で有効にします。

```bash
nix eval --raw --impure --expr '
  let hc = (builtins.getFlake (toString ./.)).homeConfigurations.default;
      probe = hc.extendModules { modules = [{ hydenix.hm.shell.fish.enable = true; }]; };
  in probe.config.programs.fish.interactiveShellInit
' | grep -n 'aurhelper\|user.fish'
```

`source …/user.fish` の行と 6 個の alias が並んで出ます。これを包む `status is-interactive; and begin` は home-manager 側が付けるので、そちらは入力を直接読みます。

```bash
HM=$(nix eval --raw --impure --expr '
  (builtins.getFlake (toString ./.)).inputs.home-manager.outPath')
grep -n 'is-interactive; and begin' -A 12 "$HM/modules/programs/fish.nix"
```

#### 確認方法 3（実機・fish 上で）

エイリアスは在るのに変数は無い、という食い違いを直接見ます。

```fish
type un            # → function un … '$aurhelper -Rns $argv' が表示される（存在する）
set -S aurhelper   # → 何も出ない（未定義）
un fastfetch       # → 失敗する
```

#### 修正方法

コメント 2 行を含めて 8 行削除するだけです。

```diff
 alias lt='eza --icons=auto --tree'
-# 注意: 以下の $aurhelper 系エイリアスは Arch の AUR ヘルパー向けで、
-# NixOS には存在しない。HyDE の設定を移植した名残であり実行しても動かない
-alias un='$aurhelper -Rns'
-alias up='$aurhelper -Syu'
-alias pl='$aurhelper -Qs'
-alias pa='$aurhelper -Ss'
-alias pc='$aurhelper -Sc'
-alias po='$aurhelper -Qtdq | $aurhelper -Rns -'
 alias vc='code'
```

NixOS 版に置き換えるのは勧めません。`up` に相当するのは `nixos-rebuild switch --flake …#<host>` ですが、flake のパスもホスト名も `sudo` の要否も利用者の構成次第で、ライブラリ側が決め打ちできる値ではありません。`nh` を使う流儀もあります（[D](#d-dotnix-側で持てばよいもの) 参照）。必要な人が自分の設定で `programs.fish.shellAliases` に書けば済む話です。

#### リスク

ありません。動いていないものを消すだけで、`fish.enable = true` の利用者にも失われる機能はありません。zsh / bash 側は無関係です（確認方法 1）。

#### 付随して直すとよい点

同じ `interactiveShellInit` にある `c` / `l` / `ls` / `ll` / `ld` / `lt` / `vc` / `fastfetch` と `..` 系は、すぐ下の `shellAliases` / `shellAbbrs`（`shell.nix:265-280`）と内容が重複しています。`alias` を消して `shellAliases` 側に寄せると、fish ブロックが素直になります。ただし挙動が変わらない整理なので、PR にするなら削除とは分けてください。

> この修正は上流へ PR を送る価値があります。A-1 と同じく小さく独立した変更で、上流の HyDE 自身がコメントアウトしている行を移植時に有効化してしまった、という経緯を本文に書けば説明も短く済みます。

### B-10. 同名アイコンテーマを複数テーマが「異なる内容」で同梱している

[santamn/hydenix#5](https://github.com/santamn/hydenix/pull/5)（`share/icons` の buildEnv 衝突修正）の調査で見つかった、同じ構造のより静かな問題です。

#### 問題

HyDE テーマの tarball は各テーマリポジトリで別々の時期に生成されているため、同じアイコンテーマ（同じ `share/icons/<dir>`）を複数のテーマが**中身の違うビルド**で同梱していることがあります。全 58 テーマの pin 済み rev を調査して、内容が食い違うペアが 4 つ確認できました（10 桁は tar.gz の blob SHA）。

| 展開先ディレクトリ | テーマ A | テーマ B |
|---|---|---|
| `Tela-circle-grey` | Catppuccin Latte `1cd2add523` | Graphite Mono `1c9e602cc5` |
| `Tela-circle-green` | Greenify `1fbe03250f` | LimeFrenzy `6b38249179` |
| `Aretha-Dark-Icons` | Amethyst-Aura `a2933d8840` | Nightbrew `a936bb73d2` |
| `Gruvbox-Plus-Dark` | AbyssGreen `99ed823d5f` | Gruvbox Retro `e944ab8ae7` |

同名で blob も一致するペア（`TelaGreen` の Decay Green / Green Lush、`Vivid-Glassy-Dark` の Another World / Code Garden など）はバイト同一なので無害です。また `Tela-circle-dracula`（5 テーマが同梱、うち Electra / Joker は別内容）と `Bibata-Modern-Ice`（Vanta Black が同梱）は standalone パッケージと衝突する側の問題で、#5 の `sharedAssets` で解決済みです。

#### 原因

[`modules/hm/theme.nix`](../modules/hm/theme.nix) は選択されたテーマを 1 つの `symlinkJoin` に束ねます。`symlinkJoin` の実体は `lndir` で、同じパスに 2 回目のエントリが来ると**警告してスキップ**します（`buildEnv` と違ってエラーにしない）。結果は「先に並んだテーマの共有ファイル ＋ 後のテーマにしかないファイル」という混成アイコンテーマで、ビルドは何事もなく通ります。表のペアを両方 `hydenix.hm.theme.themes` に入れた場合だけ発生し、デフォルトの `[Mocha, Latte]` 単独では起きません。

#### 確認方法

ネットワークだけで確認できます（clone もビルドも不要、`gh` と `jq` が必要）。

```bash
for f in pkgs/hydenix-themes/*.nix; do
  case "$f" in */default.nix) continue;; esac
  owner=$(grep -o 'owner = "[^"]*"' "$f" | head -1 | cut -d'"' -f2)
  repo=$(grep -o 'repo = "[^"]*"' "$f" | head -1 | cut -d'"' -f2)
  rev=$(grep -o 'rev = "[a-f0-9]*"' "$f" | head -1 | cut -d'"' -f2)
  gh api "repos/$owner/$repo/git/trees/$rev?recursive=1" \
    --jq '.tree[] | select(.path|test("(Icon|Cursor)_[^/]*\\.tar\\.gz$")) | "\(.sha[0:10])  \(.path)"' \
    | sed "s|^|$(basename "$f" .nix)  |"
done
```

読み方の注意が 2 つあります。

- **owner / repo は必ずテーマごとに読むこと。** 58 テーマ中 37 個は `HyDE-Project/hyde-themes` ではなく専用リポジトリにあります。全 rev を `hyde-themes` に対して照会すると 44 件が 404 になり、「pin が壊れている」ように見えますが、それはリポジトリ違いによる誤検出です（実際には 58 件すべて到達可能でした）。
- **tarball 名と展開先ディレクトリ名は一致しないことがある。** Joker は `Icon_Tela-circle-dracula.tar.gz`（他は `Icon_TelaDracula.tar.gz`）、Electra の `Cursor_Electra.tar.gz` は `Nero-Cyber-Cyan` に展開されます。blob が違う同名 tarball を見つけたら、最終判断は raw URL から取得して `tar -tzf` で top-level を見ること。

#### 実害

該当ペアを両方有効にしてテーマを切り替えると、アイコンの一部だけ別ビルド由来になります。サイズ違い・デザイン改版の混在なので視覚的な破綻は軽微ですが、「テーマを切り替えたのに一部のアイコンが変わらない」形で表面化し、原因究明が非常にしづらい類のバグです。

#### 修正方法

#5 で入れた `sharedAssets`（展開先ディレクトリ名 → 正準パッケージの attrset。該当ディレクトリを展開後に正準パッケージへの symlink に置き換える）がそのまま受け皿になります。ペアごとに正準ソースを 1 つ決めて登録するだけです。

| ディレクトリ | 正準ソース候補 |
|---|---|
| `Tela-circle-grey` / `Tela-circle-green` | nixpkgs `tela-circle-icon-theme.override { colorVariants = ["grey" / "green"]; }`（`Tela-circle-dracula` と同じ作り） |
| `Gruvbox-Plus-Dark` | nixpkgs `gruvbox-plus-icons`（展開先ディレクトリ名が一致するかは要確認） |
| `Aretha-Dark-Icons` | nixpkgs に無い。どちらかのテーマの blob を `fetchurl` で固定して 1 回だけ展開する小パッケージを作るか、原作者リポジトリから `fetchFromGitHub` する |

`sharedAssets` は「そのディレクトリを同梱していたテーマだけ」を置き換えるので、`home.packages` に増えるものはなく、該当テーマを有効にした人の閉包にだけ正準パッケージが入ります。あわせて `checks.theme-assets`（`buildEnv` はテーマを別 paths として突き合わせるので、`symlinkJoin` と違って同名衝突を検出できる）に該当テーマを足すと、正準化漏れが CI で落ちるようになります。

> 前提となる #5 は `main` にマージ済みなので、そのまま積み増せます。優先度は B の末尾（ビルドは壊れず、特定の組み合わせでしか起きない）。

---

## C. 優先度: 低（仕様として割り切れるもの）

| 項目 | 内容 | 確認方法 | 対応の方向性 |
|---|---|---|---|
| `pyprland` が使えない | 本家 issue #188（`hyde-shell pypr console` が動かない）が未解決。フォークでは imports もオプションも削除済み | `grep -rn "pyprland" modules/` → コメントアウト行しか出ない | 上流の HyDE 側の問題。scratchpad が欲しくなったら再検討 |
| `nix`/`sddm`/`system` が `enable` に従わない | `default = true` 固定（[07-5](./07-reading-notes.md)） | `grep -rn "default = config.hydenix.enable\|default = true;" modules/system/*.nix` → `nix.nix` / `sddm.nix` / `system.nix` だけが `true` 固定 | `config.hydenix.enable` に揃えるべきだが、既存利用者の環境が変わるので慎重に |
| 履歴の環境変数が `xdg.nix` にある | 本家 issue #154 | `grep -n "HIST" modules/hm/xdg.nix` → `HISTFILE` / `HISTSIZE` / `SAVEHIST` が出る | 移すだけなら 10 行の移動で済む。ただし 9 行中 6 行は誰も読まない（[C-2](#c-2-履歴の環境変数を-shellnix-へ移す本家-issue-154)） |
| `.config/waybar/modules` を配置している | 本家 TODO のもう配置不要ではという指摘が残存 | `grep -rn "waybar/modules" modules/` → `waybar.nix` と `hyde.nix` の 2 か所で配置 | 実機で外して試さないと判断できない |
| hyprlock が `hyprland/` の外にある | `lockscreen.nix` のまま。hyprlock と swaylock の排他 assertion も無い | `ls modules/hm/hyprland/ modules/hm/lockscreen.nix` で配置を見る | 設計上の課題。統合するなら大きめの変更 |
| `hyde config.toml` がオプション化されていない | mutable なので手で編集するしかない | `grep -n -A4 '".config/hyde/config.toml"' modules/hm/hyde.nix` → `source` + `mutable = true` のみ | Nix オプション化は大仕事。効果も限定的 |
| `kdePackages.kconfig` の要否 | コード中に TODO が残っている | `grep -n "kconfig" modules/hm/hyde.nix` → TODO コメント付きで残っている | 外して動くか実機で確認するだけ |
| GTK テーマ初回変更時のちらつき | `gtk.nix` に TODO | `grep -n "TODO" modules/hm/gtk.nix`。再現は実機でテーマを切り替えるしかない | 原因不明。優先度低 |
| spicetify 対応 | `spotify.nix` に TODO | `grep -n "TODO" modules/hm/spotify.nix` → 案のコメントだけで実装は無い | flatpak 前提の案が書かれているだけ |
| 本家 issue #182: hypr windowrules errors | 状態不明。HyDE の bump で解消した可能性あり | 実機で `hyprctl configerrors`（何も出なければ解消済み） | まず再現するか確認 |

### C-1. テーマ適用を Nix 側で再現する（`theme.nix` の TODO）

[`modules/hm/theme.nix`](../modules/hm/theme.nix) に残っている TODO の検討です。

> `#TODO: this works but a more robust implementation is possible. just do what
> theme.set.sh/dconf.set.sh does and use home.file to set the correct gtk/qt/etc options`

実現すれば activation script も systemd サービスも mutable ファイルも減らせます。ただしそのまま実行することはできません。理由を先に 2 つ挙げます。

1. TODO が名指ししている 2 本のスクリプトは、もう存在しません（B-8）。現在の相当物は `theme.switch.sh` と `color.set.sh` / `color/dconf.sh` です。TODO を書いた時点の HyDE と現在の HyDE では構造が変わっています。
2. 一部だけ Nix 化するということができません。後述の「なぜ中途半端にできないのか」を参照。

#### 何を Nix 化できるのか

`theme.switch.sh` がやっていることは、静的（選んだテーマ名だけで決まる）と動的（現在の壁紙に依存する）にきれいに二分できます。

静的な側は `theme.active` が決まれば内容が確定するので、ビルド時に生成できます。

| 生成先 | 現在の書き手 | 内容 |
|---|---|---|
| `~/.config/gtk-3.0/settings.ini` | `theme.switch.sh`（`toml_write`） | gtk-theme-name / icon / cursor / font |
| `~/.gtkrc-2.0` | `theme.switch.sh`（`sed -i`） | 同上（GTK2） |
| `~/.config/xsettingsd/xsettingsd.conf` | `theme.switch.sh`（`sed -i`） | `Net/ThemeName` ほか |
| `~/.config/qt5ct/qt5ct.conf`, `qt6ct/qt6ct.conf` | `theme.switch.sh`（`toml_write`） | `Appearance/icon_theme`, `Fonts` |
| `~/.config/kdeglobals` | `theme.switch.sh`（`toml_write`） | `Icons/Theme`, `widgetStyle=kvantum` |
| `~/.local/share/icons/default/index.theme`, `~/.icons/default/index.theme` | `theme.switch.sh` | カーソルテーマの継承 |
| `~/.Xresources` / `~/.Xdefaults` | `theme.switch.sh` | `Xcursor.theme` / `Xcursor.size` |
| `~/.config/gtk-4.0`（シンボリックリンク） | `theme.switch.sh` | テーマの `gtk-4.0` へのリンク |
| `~/.config/hypr/themes/theme.conf` | `theme.switch.sh`（`sanitize_hypr_theme`） | `hypr.theme` から `exec` と shadow 系を除いたもの |
| dconf（`org/gnome/desktop/interface` ほか） | `color/dconf.sh` | GTK / icon / cursor / font / color-scheme |

動的な側は現在の壁紙に依存するので、実行時に生成するしかありません。

- wallbash の色生成一式（`hypr/themes/colors.conf`, `waybar/theme.css`, `kitty/theme.conf`, `dunst/dunstrc`, `rofi/theme.rasi`, Kvantum, VS Code …）
- 壁紙そのものの適用（`wallpaper.sh`）
- `qt5ct/colors/wallbash.conf` など wallbash 由来の配色ファイル

したがって TODO は静的な側だけなら実現可能で、動的な側は残ります。mutable ファイルを全廃できるわけではない、というのが最初に押さえるべき点です。

#### なぜ中途半端にできないのか

上の表の静的な生成先はすべて `theme.switch.sh` も書きに来ます。Nix が `settings.ini` を store へのシンボリックリンクとして置くと、`toml_write` が読み取り専用のリンク先に書こうとして失敗します。

つまり Nix 側で書くなら、`theme.switch.sh` の静的な部分を呼ばないようにする必要があります。HyDE にそれを止めるフラグはないので、取れる道は次の 3 つです。

| 案 | 内容 | 評価 |
|---|---|---|
| 1 | `theme.switch.sh` を呼ぶのをやめ、動的な側（`wallpaper.sh`）だけ直接呼ぶ | 本命。下で詳述 |
| 2 | `pkgs/hyde` で `theme.switch.sh` にパッチを当てて静的部分を削る | 非推奨。行番号決め打ちの `sed` は既に一度失敗して[コメントアウト済み](../pkgs/hyde/default.nix)（`sed -i '187,190d'`） |
| 3 | mutable のまま両方に書かせる | 現状。何も得られない |

案 1 は、`theme.switch.sh` の末尾がやっていることをそのまま引き継ぐ形になります。

```bash
# theme.switch.sh:239 — 動的な側の入口はここ 1 行
"$LIB_DIR/hyde/wallpaper.sh" -s "$(readlink "$HYDE_THEME_DIR/wall.set")" --global
```

ただし `wallpaper.sh` は `HYDE_THEME` と `HYDE_THEME_DIR` が設定済みであることを前提にしています。`theme.switch.sh:121` の `set_conf "HYDE_THEME" "$themeSet"` と、`globalcontrol.sh` / `env-theme` の読み込みに相当する処理は Nix 側で用意する必要があります。

#### 設計上の分岐点: テーマのメタデータをどこから取るか

静的な側を生成するには `GTK_THEME` / `ICON_THEME` / `CURSOR_THEME` / フォント名を知る必要があります。これらの出どころはテーマパッケージ内の `hypr.theme` です。

```bash
# 例: Catppuccin Macchiato
$GTK_THEME=Catppuccin-Macchiato
$ICON_THEME = Tela-circle-dracula
$COLOR_SCHEME = prefer-dark
```

書かれていない変数は [`Configs/.local/share/hyde/env-theme`](https://github.com/HyDE-Project/HyDE/blob/master/Configs/.local/share/hyde/env-theme) の既定値にフォールバックします。上の例のようにテーマ側は 3 つしか上書きしないことが多いので、テーマごとに持つべきデータは実際には少数です。実際の分布は次で数えられます。

```bash
# 実機で。各テーマの hypr.theme が上書きしている変数を集計する
grep -h '^\$' ~/.config/hyde/themes/*/hypr.theme \
  | sed 's/ *=.*//' | sort | uniq -c | sort -rn
```

取りうる実装は 3 つあります。

| 案 | 方法 | 判定 |
|---|---|---|
| A | eval 時に `builtins.readFile "${themePkg}/…/hypr.theme"` で読む | 不可。IFD になる |
| B | `runCommand` の中で `hypr.theme` を読んで設定ファイルを生成する | 可。ただし値が Nix から見えない |
| C | 各テーマの `.nix` にメタデータを宣言する | 推奨 |

案 A が使えないのは、テーマパッケージが derivation だからです。その出力を eval 時に `readFile` すると import-from-derivation になり、評価のたびにテーマのビルドが走ります。`nix flake check` や CI の eval が重くなり、`--no-allow-import-from-derivation` では落ちます。

なお、パスが eval 時に分かること自体は問題ありません。ビルドを伴わずに解決できます。

```bash
nix eval --impure --raw --expr '
  let hc = (builtins.getFlake (toString ./.)).homeConfigurations.default;
  in hc.config.home.file.".config/hyde/themes/Catppuccin Mocha".source'
# => /nix/store/…-Catppuccin-Mocha/share/hyde/themes/Catppuccin Mocha
```

問題になるのは中身を読むときだけです。

案 B は、`pkgs.runCommand` の中で `hypr.theme` を `sed` / `hyq` で解析し、`settings.ini` などを出力するディレクトリを作って `home.file.….source` に渡すものです。IFD にはならず、58 テーマ分のデータ入力も不要です。ただし値が Nix の世界に出てこないため、home-manager の `dconf.settings` / `gtk.*` / `qt.*` といった既存モジュールには載せられず、利用者が個別の値を上書きすることもできません。

案 C はテーマ定義そのものに書く方法で、これを推奨します。

```nix
# pkgs/hydenix-themes/Catppuccin-Macchiato.nix
mkTheme rec {
  name = "Catppuccin Macchiato";
  settings = {
    gtkTheme = "Catppuccin-Macchiato";
    iconTheme = "Tela-circle-dracula";
    colorScheme = "prefer-dark";
    # 未指定は env-theme 相当の既定値へ
  };
  src = pkgs.fetchFromGitHub { … };
}
```

こうすると値が eval 時に見えるので、hydenix が設定ファイルを手書きする必要がなくなります。home-manager の `gtk` / `qt` / `dconf` モジュールがすでに `settings.ini` / `.gtkrc-2.0` / dconf の書き方を知っているので、そちらに委譲できます。これが本当の利得で、案 B では得られません。

58 ファイルへの手入力が要るように見えますが、`hypr.theme` から値を抽出して `.nix` を生成するスクリプトを書けば済みます。B-7 の修正が同じ 58 ファイルに `ref` を足す作業なので、まとめてやるのが効率的です。上流のテーマが値を変えたときに備えて、抽出結果と `.nix` の差分を CI で検出する仕組みも同時に入れておくとよいでしょう。

#### 段階的な進め方

1. B-8 を先に片付ける（死んだサービスの削除）。単独で価値があり、依存もありません
2. テーマ定義に `settings` を足し、抽出スクリプトと CI の drift 検出を用意する（案 C）
3. dconf だけ home-manager の `dconf.settings` に移す。`setThemeDconf.service` が不要になり、3 段構えが 2 段になります
4. GTK / Qt / カーソルを `gtk.*` / `qt.*` と `home.file` に移し、対応する mutable 指定を外す
5. `theme.switch.sh` の呼び出しを `wallpaper.sh` の直接呼び出しに置き換える（案 1）

3 まで進めた時点で、初回 rebuild で dconf が失敗する問題は消えるはずです。home-manager の dconf モジュールは D-Bus セッションが無い場合の面倒を自前で見ますが、activation 時の挙動は実機で確認してください（`journalctl --user` と `dconf dump /org/gnome/desktop/interface`）。ここは未検証です。

#### 効果と費用

得られるものは 3 つです。

- 3 段構えの適用が減り、初回 rebuild の失敗が消える
- テーマ設定が Nix の世界に入るので、利用者が普通の home-manager オプションで上書きできる
- dry-activate が正しく動くようになる（A-2 にも効く）

失うもの・費用は次のとおりです。

- 上流追従コストが上がります。`theme.switch.sh` が変わるたびに Nix 側の再現も追う必要があります。この危険は仮定の話ではなく、`dconf.set.sh` から `color/dconf.sh` への改名に追従できていない B-8 が実例です。HyDE のスクリプトを呼ぶだけなら改名は追従不要でした。
- A-3 の解決にはなりません。減らせるのは上の表の十数件で、mutable ファイル 115 件の大半は wallbash 由来のため残ります。
- 実機での検証が必須です。GTK4・Qt・カーソルは壊れても気づきにくい割に、壊れたときの体感は悪い部類です。

結論として、設計としては正しい方向ですが、費用に対する効果が限定的です。HyDE のスクリプトをそのまま動かすという現在の方針を捨てて hydenix がテーマ適用を自前で持つ、という方針転換を伴うので、着手するなら上流に issue を立てて合意を取ってからにすべきです。一方、段階 1（B-8）と段階 3（dconf のみ）は方針転換を伴わず単独で価値があるため、そこだけ先に進めるのは十分に現実的です。

### C-2. 履歴の環境変数を `shell.nix` へ移す（本家 issue #154）

結論から書くと、簡単に直せます。移すだけなら 10 行の移動で、挙動は変わりません。ただし調べると置き場所が変だという以上のことが分かります。この 9 行は 1 行も効いていません。

#### 問題

[`modules/hm/xdg.nix`](../modules/hm/xdg.nix) L91-100 の `home.sessionVariables` に zsh の履歴設定が置かれています。XDG とは無関係なので `shell.nix` にあるべきものです。

```nix
# History configuration // explicit to not nuke history
HISTFILE = "\${HISTFILE:-\$HOME/.zsh_history}";
HISTSIZE = "10000";
SAVEHIST = "10000";
setopt_EXTENDED_HISTORY = "true";
setopt_INC_APPEND_HISTORY = "true";
setopt_SHARE_HISTORY = "true";
setopt_HIST_EXPIRE_DUPS_FIRST = "true";
setopt_HIST_IGNORE_DUPS = "true";
setopt_HIST_IGNORE_ALL_DUPS = "true";
```

#### 原因

理由が 2 つに分かれます。

1 つ目は、`setopt_*` の 6 行に読み手が存在しないことです。`setopt_EXTENDED_HISTORY` は zsh の `setopt` とは無関係な、HyDE 側の独自変数です。しかしピン留め中の HyDE（`a51460a`）に `setopt_` という文字列は 1 か所もありません。上流のリファクタリングで無くなった変数を、hydenix が export し続けている状態です。

2 つ目は、`HISTFILE` / `HISTSIZE` / `SAVEHIST` が home-manager に上書きされることです。`shell.nix:111-112` で `programs.zsh.enable = true` にしているため、home-manager の zsh モジュール（[`modules/programs/zsh/history.nix`](https://github.com/nix-community/home-manager/blob/079a3b5d1aa6a719920a51316253b7d6dd22738d/modules/programs/zsh/history.nix)）が `.zshrc` の order 910 で同じ 3 つを書きます。

```zsh
# 生成される .zshrc
HISTSIZE="10000"
SAVEHIST="10000"
HISTFILE="/home/<user>/.config/zsh/.zsh_history"
```

`hm-session-vars.sh` を読むのは `.zshenv` / `.zprofile` で、`.zshrc` はその後に走ります。つまり後から書く home-manager が必ず勝ちます。

`HISTSIZE` / `SAVEHIST` は値が同じ（`10000`）なので差は出ませんが、`HISTFILE` は違います。`${HISTFILE:-$HOME/.zsh_history}` という書き方を尊重するのは HyDE の `Configs/.config/zsh/conf.d/hyde/terminal.zsh` L171 ですが、hydenix はこのファイルを配置していません（`shell.nix:338` でコメントアウト）。コメントにある explicit to not nuke history、すなわち既存の `~/.zsh_history` を引き継ぐ意図は達成されていないことになります。実際の履歴は `~/.config/zsh/.zsh_history` に溜まります。

#### 実害

ありません。home-manager 側の既定が十分まともなので、意図した設定が効いていないだけで壊れてはいません。効いていない設定は次の 3 つです。

| 意図した `setopt_*` | home-manager の既定 |
|---|---|
| `EXTENDED_HISTORY = true` | `NO_EXTENDED_HISTORY`（タイムスタンプを残さない） |
| `HIST_EXPIRE_DUPS_FIRST = true` | `NO_HIST_EXPIRE_DUPS_FIRST` |
| `HIST_IGNORE_ALL_DUPS = true` | `NO_HIST_IGNORE_ALL_DUPS` |

`SHARE_HISTORY` と `HIST_IGNORE_DUPS` は home-manager の既定で既に有効なので、結果的に一致しています。

#### 確認方法 1（`setopt_*` の読み手が居ないこと）

hydenix 側と HyDE 側の両方を見ます。

```bash
grep -rn 'setopt_' modules/
# => xdg.nix の定義 6 行だけ（読んでいる箇所は無い）
```

HyDE 本体はピン留め rev のアーカイブを落として grep します（`nix` は不要）。

```bash
REV=$(grep -o '"[0-9a-f]\{40\}"' pkgs/hyde/default.nix | head -1 | tr -d '"')
curl -sL "https://codeload.github.com/HyDE-Project/HyDE/tar.gz/$REV" | tar xz
grep -rI 'setopt_' "HyDE-$REV" | wc -l
# => 0
```

#### 確認方法 2（home-manager に上書きされること）

生成される `.zshrc` の中身を直接読みます。

```bash
nix eval --raw --impure --expr '
  (builtins.getFlake (toString ./.)).homeConfigurations.default
    .config.programs.zsh.initContent
' | grep -n 'HISTFILE\|HISTSIZE\|SAVEHIST'
```

`HISTFILE="/home/hydenix/.config/zsh/.zsh_history"` が出れば、export した `${HISTFILE:-$HOME/.zsh_history}` が使われていないことの証拠です。

実際に適用される `setopt` の一覧も同じ方法で見られます。

```bash
nix eval --impure --expr '
  (builtins.getFlake (toString ./.)).homeConfigurations.default
    .config.programs.zsh.setOptions'
# => [ "HIST_FCNTL_LOCK" "HIST_IGNORE_DUPS" … "NO_EXTENDED_HISTORY" "NO_HIST_IGNORE_ALL_DUPS" … ]
```

上の表のとおり `NO_` 付きで並んでいれば再現しています。実機なら次の 2 つが直接の証拠です。

```bash
grep -n 'HISTFILE\|EXTENDED_HISTORY' ~/.config/zsh/.zshrc
echo $HISTFILE          # => /home/<user>/.config/zsh/.zsh_history
```

#### 修正方法

2 つの案があります。issue #154 の文面どおりなら案 1、実態に合わせるなら案 2 です。

案 1 は移動だけの最小変更です。`xdg.nix` の該当 10 行（コメント含む）を切り取り、`shell.nix` の `config` にそのまま貼ります。zsh 専用の設定なので `zsh.enable` で括ります。

```nix
# modules/hm/shell.nix の config 内に追加
home.sessionVariables = lib.mkIf cfg.zsh.enable {
  # History configuration // explicit to not nuke history
  HISTFILE = "\${HISTFILE:-\$HOME/.zsh_history}";
  # …以下 xdg.nix からそのまま
};
```

括る条件が `hydenix.hm.xdg.enable` から `hydenix.hm.shell.enable`（＋ `zsh.enable`）に変わるだけです。どちらの既定も `config.hydenix.hm.enable` なので、既定の構成では出力が 1 バイトも変わりません。`xdg.nix` 冒頭 L3-4 の注意書きも同時に消せます。

案 2 を推奨します。死んでいる 6 行を消し、意図を home-manager のオプションで表現します。

```diff
 # modules/hm/xdg.nix
-      # History configuration // explicit to not nuke history
-      HISTFILE = "\${HISTFILE:-\$HOME/.zsh_history}";
-      HISTSIZE = "10000";
-      SAVEHIST = "10000";
-      setopt_EXTENDED_HISTORY = "true";
-      setopt_INC_APPEND_HISTORY = "true";
-      setopt_SHARE_HISTORY = "true";
-      setopt_HIST_EXPIRE_DUPS_FIRST = "true";
-      setopt_HIST_IGNORE_DUPS = "true";
-      setopt_HIST_IGNORE_ALL_DUPS = "true";
```

```diff
 # modules/hm/shell.nix の programs.zsh 内
     dotDir = "${config.xdg.configHome}/zsh";
+
+    # 履歴設定（旧: xdg.nix の setopt_* 環境変数。読み手が居なかったので HM のオプションへ移した）
+    history = {
+      extended = true;              # setopt_EXTENDED_HISTORY
+      expireDuplicatesFirst = true; # setopt_HIST_EXPIRE_DUPS_FIRST
+      ignoreAllDups = true;         # setopt_HIST_IGNORE_ALL_DUPS
+      # ignoreDups / share と size / save(=10000) は home-manager の既定と同じなので書かない
+    };
```

- `setopt_INC_APPEND_HISTORY` に対応するオプションはありませんが、不要です。zsh の `SHARE_HISTORY` は入力したコマンドを履歴ファイルへ追記する動作を含んでおり、マニュアルにもこの場合 `INC_APPEND_HISTORY` は切っておくべきと書かれています。
- `HISTFILE` は書かないのが正解です。現在の実効値は `~/.config/zsh/.zsh_history`（home-manager の既定 = `$ZDOTDIR/.zsh_history`）です。ここで `programs.zsh.history.path` を `$HOME/.zsh_history` に変えると、既存利用者の履歴が消えたように見えます（ファイルは残るが読まれなくなる）。置き場所を変えるかどうかは整理とは別の判断なので、混ぜないでください。
- `home.sessionVariables` は fish / bash からも読まれますが、fish は履歴に `HISTFILE` を使わず、hydenix は `programs.bash` を設定していないため、削除して困る利用者は居ません。

#### リスク

案 1 はゼロです（出力が変わらない）。案 2 は `.zshrc` に `setopt` が 3 つ増えるぶん挙動が変わります。特に `EXTENDED_HISTORY` は履歴ファイルの書式が `: <epoch>:<elapsed>;<コマンド>` に変わりますが、zsh は新旧どちらの行も読めるので既存の履歴が壊れることはありません。

#### 付随して直すとよい点

すぐ上の `xdg.nix:89` も同じ理由で効いていません。

```nix
ZSH_AUTOSUGGEST_STRATEGY = "history completion";
```

`shell.nix:114` で `autosuggestion.enable = true` にしているため、home-manager が `.zshrc` の order 700 で `ZSH_AUTOSUGGEST_STRATEGY=(history)`（既定値）を書き、export した値を潰します。`completion` が落ちるので、補完候補からの提案が効きません。直すなら `programs.zsh.autosuggestion.strategy = ["history" "completion"];` を書き、`xdg.nix` 側の 1 行を消します。HyDE 本家の `terminal.zsh` も `(history completion)` にしているので、意図としてはこちらが正です。

> この修正は上流へ PR を送る価値があります。issue #154 は `shell.nix` へ移すという整理の issue ですが、6 行は読み手が消滅している、3 行は home-manager に上書きされている、という調査結果を添えれば案 2 まで一度に通しやすくなります。案 1 と案 2 を分けて出す必要はありません（案 2 は案 1 を含むため）。

---

## D. dotnix 側で持てばよいもの

hydenix に無くても、利用側（`santamn/dotnix`）で解決できるものです。上流に出す必要はありません。

| 項目 | 対応 |
|---|---|
| `nh` によるガベージコレクト | dotnix の `modules/nixos/nix.nix` で持つ |
| nixos-anywhere / disko 対応 | dotnix 側で導入する |
| 多ホスト構成 | dotnix の `mkHost` / `hosts/` で対応済み。hydenix と両立する |

---

## E. すでに解決済み

### E-1. このフォーク（santamn）で直したもの

いずれも `main` にマージ済みで、上流へそのまま出せる形になっています。

| PR | 項目 | 内容 |
|---|---|---|
| [#3](https://github.com/santamn/hydenix/pull/3) | 素材の取得元 | `Bibata-Modern-Ice` / `Tela-circle-dracula` を可変ブランチ ref の `fetchurl` から nixpkgs のソースへ。あわせて `checks` に追加 |
| [#4](https://github.com/santamn/hydenix/pull/4) | hyprcursor | nixpkgs が XCursor しか作らないため hyprcursor 版を作り直している理由をコメント化 |
| [#5](https://github.com/santamn/hydenix/pull/5) | `share/icons` の衝突 | `mkTheme` に `sharedAssets` を追加し、テーマ同梱コピーを正準パッケージへの symlink に置換。`checks.theme-assets` で CI 検出 |
| [#6](https://github.com/santamn/hydenix/pull/6) | `hyprsunset` 未インストール | 設定だけ配置されて本体が無く、毎回 `Executable not found` 通知が出ていた |
| [#7](https://github.com/santamn/hydenix/pull/7) | `hyde-shell` が source できない | `wrapProgram` の `exec` が source 元プロセスを置き換えるため、`hyprlock.sh` 等が 1 行目で終了していた |
| [#8](https://github.com/santamn/hydenix/pull/8) | Python インタプリタ不在 | 実行時 uv venv のパスを `hydePython` に置換。waybar の該当モジュールが空になる問題 |
| [#9](https://github.com/santamn/hydenix/pull/9) | swaync のプロセス名 | `pgrep -x swaync` を `.swaync-wrapped` に置換。通知センターが開かなかった |

### E-2. 本家 → 上流フォークで直ったもの

同じ問題を再度報告しないための記録です。

| 項目 | フォークでの状態 |
|---|---|
| nixpkgs / home-manager / Hyprland / HyDE の陳腐化 | 全て追従（renovate + workflow で自動化） |
| 本家 issue #169: `programs.git.settings.user.email` の型エラー | `git.nix` をモジュールごと削除 |
| 行番号決め打ちの `sed`（HyDE 更新で誤爆する） | コメントアウト |
| standalone home-manager 対応 | `homeConfigurations.default` を追加 |
| `nixosOptionsDoc` によるドキュメント生成 | mdbook + options ページ（GitHub Pages） |
| overlay の名前空間ネスト解消 | `pkgs/` へ再編 |
| demo VM | `demo/` を追加 |
| バイナリキャッシュ | 部分的。`nixConfig` に hyprland cachix を追加 |
| hyprland モジュールの重複 | `mkHyprConfig` で一本化 |
| 必須アサーション（hostname 等） | 既定値 + `mkDefault` に変更 |
