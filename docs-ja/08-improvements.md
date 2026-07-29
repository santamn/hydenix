# 08. 将来加えると良い変更

「直したほうがよい」と判断した箇所の一覧です。
上のものほど優先度が高く、下にいくほど「踏んでも仕様」と割り切れるものになります。

各項目は **問題 → なぜ起きる → 確認方法 → どう直す** の順で書いています。
指摘を鵜呑みにせず、まず **確認方法** を手元で実行して再現させてください。

---

## 確認方法の共通手順

確認には 2 種類あります。

| 種類 | 内容 |
|---|---|
| `grep` で足りるもの | コードの形を見れば分かる（書き間違い・書き漏らし） |
| `nix eval` が要るもの | 「実際に評価するとどうなるか」を見ないと分からない |

`nix eval` を使う項目は**リポジトリのルートで**実行してください。
`/etc/nix/nix.conf` に `experimental-features = nix-command flakes` が入っている前提です
（hydenix / NixOS 環境では既定で有効。無ければ `--extra-experimental-features 'nix-command flakes'` を足す）。

ほとんどの確認は **flake の `homeConfigurations.default` を評価するだけ**で、
ビルドもアクティベーションも走りません。初回は依存 flake の取得で数分かかりますが、
2 回目以降は数秒です。

以降の例は共通してこの形をとります。

```bash
nix eval --impure --expr '
  let hc = (builtins.getFlake (toString ./.)).homeConfigurations.default;
  in <調べたいもの>
'
```

- `--impure` は `builtins.getFlake` を使うために必要です
- `toString ./.` はカレントディレクトリの絶対パスになります
- git の作業ツリーが汚れていると `warning: Git tree ... is dirty` が出ますが、**評価は通ります**。追跡済みファイルの未コミット変更はそのまま評価されます
- ただし **git に未追加（untracked）のファイルは flake から見えません**。新しいファイルを足して確認するときは先に `git add` してください
- 式の中に `foldl'` のようなアポストロフィが含まれる場合、シェルのシングルクォートを一度閉じる必要があります（`builtins.foldl'"'"'` のように書くか、式をファイルに書いて `nix eval --impure --file` を使う）

「設定をいじったらどうなるか」を試したいときは `extendModules` を使います。
`configuration.nix` を書き換えずに済むので、確認用途にはこちらが便利です。

```bash
nix eval --impure --expr '
  let hc = (builtins.getFlake (toString ./.)).homeConfigurations.default;
      probe = hc.extendModules { modules = [{ <試したい設定> }]; };
  in <probe.config.… を調べる>
'
```

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

**確認方法**: 「依存先として書かれている名前」と「実在するエントリ名」を突き合わせます。

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

`after` が指している `mutableGeneration` が `false`（実在しない）である一方、
実際のエントリは `mutableFileGeneration` として存在しています。
**それでもエラーにならず評価が通っている**ことが、
「DAG が存在しない依存名を黙って無視する」ことの証拠です。

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

**確認方法**: 生成された activation script を直接読みます。

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

`$DRY_RUN_CMD` が 1 つも付いていないことが確認できます。
`createCavaConfig` の部分を `setTheme` / `createHyprConfigs` に変えれば他の 2 つも同様に見られます。
対比のため `mutableFileGeneration` も同じ方法で表示すると、
そちらには `$DRY_RUN_CMD cp ...` と付いているのが分かります。

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

**確認方法 1（影響範囲を数える）**: mutable なファイルの一覧を出します。

```bash
nix eval --impure --expr '
  let hc = (builtins.getFlake (toString ./.)).homeConfigurations.default;
      mut = builtins.filter (f: f.mutable or false) (builtins.attrValues hc.config.home.file);
  in { count = builtins.length mut; targets = builtins.map (f: f.target) mut; }'
```

執筆時点で **115 件**でした。これがすべて「設定から消しても残るファイル」です。
（`grep -rn "mutable = true" modules/ | wc -l` は宣言の数（60）なので、
`mkHyprConfig` などのループで増える分は数えられません。実数を見るには上の方法が必要です。）

**確認方法 2（実機で残留を見る）**: mutable ファイルは**シンボリックリンクではなく実ファイル**です。

```bash
# リンクなら "-> /nix/store/..." が出る。実ファイルならパスだけが出る
ls -l ~/.config/kitty/theme.conf ~/.config/hypr/keybindings.conf

# home-manager 管理下の実ファイル（＝ mutable なもの）を一覧する
find ~/.config/hypr ~/.config/waybar -maxdepth 1 -type f
```

残留そのものを再現するなら、`mutable = true` のモジュールを 1 つ無効にして
`nixos-rebuild switch` した後、該当ファイルがまだ存在することを確認します。

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

### A-4. `mutable` オプションが `xdg.configFile` に生えていない

**問題**: `modules/hm/mutable.nix` は `home.file` / `xdg.configFile` / `xdg.dataFile` の
**3 つ**に `mutable` を追加しているつもりですが、実際に生えるのは **2 つ**です。
`xdg.configFile.<name>.mutable` は存在しません。

該当箇所は [`modules/hm/mutable.nix`](../modules/hm/mutable.nix) の `options` ブロック末尾です。

```nix
mergeAttrsList = builtins.foldl' lib.mergeAttrs {};   # ← ここ
...
mergeAttrsList (
  map (attrPath: lib.setAttrByPath attrPath (lib.mkOption {type = fileAttrsType;})) fileOptionAttrPaths
)
```

**なぜ起きるか**: `lib.mergeAttrs` の実体は `x: y: x // y` で、
**トップレベルのキーしか見ない浅いマージ**です。
`map` が作るのは次の 3 つの属性集合ですが、

```nix
[ { home = { file       = OPT; }; }
  { xdg  = { configFile = OPT; }; }
  { xdg  = { dataFile   = OPT; }; } ]
```

`//` で畳み込むと `xdg` というキーが**丸ごと後勝ちで置き換わり**ます。

```nix
{}
// { home = {file = OPT;}; }        # => { home = {file = OPT;}; }
// { xdg  = {configFile = OPT;}; }  # => { home = …; xdg = {configFile = OPT;}; }
// { xdg  = {dataFile = OPT;}; }    # => { home = …; xdg = {dataFile   = OPT;}; }
                                    #                      ↑ configFile が消える
```

`fileOptionAttrPaths` の 3 要素のうち、**先頭 2 階層が衝突する `xdg.*` の 2 つで
後ろだけが残る**という形です。`home.file` と `xdg.dataFile` は無事で、
`xdg.configFile` だけが落ちます。

なお `config` 側は `file.mutable or false` と `or` でフォールバックしているため、
オプションが無くても評価は通ります。**エラーも警告も出ません。**

**実害**: **現時点ではありません。** hydenix 内の `mutable = true` は
すべて `home.file` 経由で書かれており、`xdg.configFile` / `xdg.dataFile` は
このリポジトリのどこからも使われていないためです。

```bash
grep -rn "xdg.configFile\|xdg.dataFile" modules/   # コメント行しかヒットしない
```

ただし利用者が `xdg.configFile."foo".mutable = true;` と書くと、
モジュールシステムが「そんなオプションは無い」というエラーで落ちます。
[04-mutable-files.md](./04-mutable-files.md) の記述とも食い違うため、
**潜在バグ**として直しておく価値があります。

**確認方法 1（最小再現）**: hydenix を評価せず、`lib` の挙動だけを見ます。数秒で終わります。

```bash
nix eval --impure --expr '
  let lib = (builtins.getFlake "nixpkgs").lib;
      paths = [["home" "file"] ["xdg" "configFile"] ["xdg" "dataFile"]];
  in builtins.attrNames
       (builtins.foldl'"'"' lib.mergeAttrs {} (map (p: lib.setAttrByPath p "OPT") paths)).xdg
'
# => [ "dataFile" ]        ← configFile が消えていれば再現
```

`builtins.getFlake "nixpkgs"` は flake レジストリ経由で nixpkgs を引くので、
hydenix の `flake.lock` とは無関係に単体で走ります。

`lib.mergeAttrs` を `lib.recursiveUpdate` に替えるだけで直ることも、同じ式で確認できます。

```bash
nix eval --impure --expr '
  let lib = (builtins.getFlake "nixpkgs").lib;
      paths = [["home" "file"] ["xdg" "configFile"] ["xdg" "dataFile"]];
  in builtins.attrNames
       (builtins.foldl'"'"' lib.recursiveUpdate {} (map (p: lib.setAttrByPath p "OPT") paths)).xdg
'
# => [ "configFile" "dataFile" ]     ← 両方残る
```

**確認方法 2（実際のモジュールで確認）**: 3 つのオプションの submodule に
`mutable` が居るかどうかを直接調べます。

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

**直し方**: 畳み込みの関数を深いマージに替えるだけです。

```diff
-    mergeAttrsList = builtins.foldl' lib.mergeAttrs {};
+    mergeAttrsList = builtins.foldl' lib.recursiveUpdate {};
```

`lib.mkMerge` を使って `options = lib.mkMerge (map ... )` とする手もありますが、
`recursiveUpdate` のほうが変更が 1 行で済みます。

**リスク**: 低。`xdg.configFile` に**オプションが増えるだけ**で、既存の挙動は変わりません
（誰も使っていないため）。ただし `home.file` と `xdg.configFile` の両方に
同じパスを書いている設定があると、これまで無視されていた `mutable` が効き始める
可能性はあります。修正後に確認方法 2 が 3 つとも `true` になることを確かめてください。

> この修正も上流へ PR を送る価値があります。A-1 と同様、小さく独立した変更です。

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

**確認方法**: メタ情報を直接読みます。ビルドは走りません。

```bash
nix eval --impure --expr '
  (builtins.getFlake (toString ./.)).packages.x86_64-linux.hydectl.meta.mainProgram
'
# => "hyde-ipc"     ← "hydectl" ならば修正済み
```

darwin 上でも `x86_64-linux` の**評価**はできます（ビルドはできません）。

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

**確認方法**: `sha256 = ""` は「全ゼロのハッシュ」に正規化されます。
これは実在しないハッシュなので、fetch は必ず不一致で失敗します。

```bash
nix eval --impure --expr '
  (builtins.getFlake (toString ./.)).packages.x86_64-linux.hyde-gallery.src.outputHash
'
# => "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="   ← 全ゼロなら再現
```

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

**確認方法**: 検証されている `keybindings` と並べて、両方に空文字を与えます。
**片方しか怒られない**なら再現です。

```bash
nix eval --impure --expr '
  let hc = (builtins.getFlake (toString ./.)).homeConfigurations.default;
      probe = hc.extendModules { modules = [{
        hydenix.hm.hyprland.hyprsunset.overrideConfig = "";
        hydenix.hm.hyprland.keybindings.overrideConfig = "";
      }]; };
  in probe.config.home.file'
```

実行結果（エラー終了します。それが期待どおりです）:

```
error:
Failed assertions:
- hydenix.hm.hyprland.keybindings.overrideConfig is set but empty. …
```

`keybindings` は報告されるのに `hyprsunset` は 1 行も出てきません。
修正後は 2 件とも列挙されるようになります。
`grep -n "overrideConfig" modules/hm/hyprland/assertions.nix` でも、
`hyprsunset` だけが 2 つのリストに載っていないことが確認できます。

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

**確認方法**: オプション定義の**優先度**を見ます。
`mkDefault` が付いていれば `1000`、素の代入なら `100` になります。

```bash
nix eval --impure --expr '
  (builtins.getFlake (toString ./.)).homeConfigurations.default
    .options.home.stateVersion.highestPrio
'
# => 100      ← 素の代入（mkDefault 済みなら 1000）
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

**確認方法**: `grep -n "rev\|sha256" pkgs/hyde-diff-upstream/default.nix` で
`rev = "master"` と固定ハッシュが同居していることを見るのが手っ取り早いです。

実際に破綻しているかどうかは、上流の現在の `master` と
記録されたハッシュを突き合わせるしかありません（ネットワークアクセスが要ります）。

```bash
nix-prefetch-git --quiet https://github.com/HyDE-Project/HyDE master | grep hash
# 出力が pkgs/hyde-diff-upstream/default.nix の sha256 と違えば、既に失敗する状態
```

**直し方の選択肢**:

1. `sha256 = lib.fakeSha256;` にして「毎回エラーメッセージから正しい値を取る」運用にする
2. CI（renovate）でこのハッシュも自動更新の対象にする
3. `--impure` 前提のスクリプトに書き換え、Nix の外で `git clone` する

2 が実用的ですが、renovate の設定が複雑になります。
現状は「使うときに手で更新する」で運用できているので、優先度は低めです。

### B-6. `cfg.vim or cfg.neovim` — `or` が論理和として書かれている

```nix
# modules/hm/editors.nix
(lib.mkIf (cfg.vim or cfg.neovim) {
  ".config/vim/colors/wallbash.vim" = {...};
  ".config/vim/hyde.vim" = {...};
  ".config/vim/vimrc" = {...};
})
```

**問題**: `vim = false; neovim = true;` にしても、この `mkIf` は `false` になります。
配置されるはずの `.config/vim/` 一式（wallbash 配色・vimrc）が置かれません。

**なぜ起きる**: Nix の `or` は**属性が存在しないときの既定値**を与える演算子で、
判定するのは値の真偽ではなく**キーの有無**です。

```nix
{a = false;}.a or true   # => false （a は存在するので、その値がそのまま返る）
{}.a or true             # => true  （a が無いので既定値）
```

`cfg.vim` は `options` ブロックで `default = true` 付きで宣言されているため、
モジュール評価の時点で**必ず存在します**。よって `cfg.vim or cfg.neovim` は
どう設定しても `cfg.vim` と等価で、`cfg.neovim` は一度も参照されません。

Python / Lua / Ruby の `a or b`（a が偽なら b）と同じ語感で書くと、
Nix では静かに意味が変わります。`cfg.vim` は属性選択式なので
**構文エラーにも型エラーにもならず評価が通ってしまう**のが厄介な点です。

**確認方法**: `vim = false; neovim = true;` にして、
配置されるはずの `.config/vim/vimrc` が居るかを見ます。

```bash
nix eval --impure --expr '
  let hc = (builtins.getFlake (toString ./.)).homeConfigurations.default;
      probe = hc.extendModules { modules = [{
        hydenix.hm.editors.vim = false;
        hydenix.hm.editors.neovim = true;
      }]; };
  in builtins.hasAttr ".config/vim/vimrc" probe.config.home.file'
# => false     ← 配置されていない。修正後は true になる
```

`vim = true` に戻すと `true` が返ります。
`neovim` の値を何に変えても結果が動かないことも、同じ方法で確かめられます。

**直し方**:

```diff
-(lib.mkIf (cfg.vim or cfg.neovim) {
+(lib.mkIf (cfg.vim || cfg.neovim) {
```

配置対象は vim / neovim のどちらからも使える `.config/vim/` 配下のファイルなので、
「どちらか一方でも有効なら配置する」という元の設計意図は妥当です。
演算子の選択だけが誤っている状態で、意図を変える変更ではありません。

**PR の出し方**: 1 文字の変更ですが挙動が変わるので、他の修正と混ぜず単独 PR にします。
「`or` は attribute fallback であって論理和ではない」という説明を本文に添えてください。
既定値が両方 `true` のため、既存利用者のうち `vim = false` を明示している人だけに影響します。

### B-7. テーマ自動更新が一度も動いていない

**問題**: [`scripts/update-themes.sh`](../scripts/update-themes.sh) と
[`update-themes.yml`](../.github/workflows/update-themes.yml) は
「テーマの `rev` / `sha256` を定期更新する」ための仕組みですが、
**実際には `rev` も `sha256` も一度も更新されていません**。
毎日 0:00 UTC に起動して、差分ゼロで PR を作らずに終わっています。

**なぜ起きるか**: スクリプト冒頭の分岐が原因です。

```bash
# scripts/update-themes.sh:28-31
if [[ "$CURRENT_REV" =~ ^[0-9a-f]{40}$ ]]; then
  LATEST_COMMIT_HASH="$CURRENT_REV"     # ← 「最新」＝「今の値」と決めつけている
```

`rev` がコミットハッシュなら「最新コミット＝今のコミット」とみなし、
以降は `sha256` を再検証するだけの分岐に入ります。
しかし**同じコミットのアーカイブは当然同じハッシュ**になるので、
この検証は必ず一致し、必ず `already up to date` で終わります。

そして `pkgs/hydenix-themes/` のテーマ 58 ファイルが、例外なく 40 桁の
コミットハッシュで固定されています。つまり、

- ブランチ名を解決する `else` 側（L32-42）には**永久に到達しない**
- `rev` を書き換える `sed`（L76）も**永久に実行されない**

おそらく初回実行時に「ブランチ名 → コミットハッシュ」への置換が一度だけ走り、
**それ以降は自分で自分を凍結してしまった**、という自己無効化のパターンです。

**実害**: テーマが upstream に追従しません。
壁紙の追加や `.dcol` の修正が反映されないだけなので破壊的ではありませんが、
「自動更新されているつもり」で放置されるぶん質が悪いです。

**確認方法 1（pin がすべてハッシュであること）**:

```bash
grep -o 'rev = "[^"]*"' pkgs/hydenix-themes/*.nix | grep -cv '[0-9a-f]\{40\}'
# => 0     ← ブランチ名で pin されたファイルが 1 つも無い＝else 側に入らない
```

**確認方法 2（一度も自動コミットされていないこと）**:

```bash
git log --all --oneline --grep="chore(themes)"
# => e561f90 chore(themes): `Ice-Age`: bump hash
```

workflow が付けるはずの `chore(themes): automated theme updates` は
**履歴に 1 件も存在しません**。唯一のハッシュ更新は人間による手動コミットです。

**確認方法 3（実際の陳腐化を数える）**: `git ls-remote` で追跡先の HEAD と突き合わせます。
ネットワークアクセスが要りますが、clone はしないので 1〜2 分で終わります。

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

2026-07 時点の結果は **58 件中 11 件が upstream に遅れ**ていました。

```
1-Bit: ee6a1336 -> 84b2f94e            Moonlight:       cc389fdc -> 50f77a6e
Breezy-Autumn: db980839 -> 959294bf    Obsidian-Purple: d1c90091 -> b73f00b1
Cosmic-Blue: f5e0e85d -> ad8a9a50      Peace-Of-Mind:   45ee6f24 -> 632fb4a0
Crimson-Blue: 5bc78a51 -> ee6da6ff     Timeless-Dream:  8a10d655 -> 5104d77c
Electra: 61cd9718 -> 953676ce          Monterey-Frost:  4675ddd4 -> 559edd92
Grukai: 95e0b926 -> 3945b4a1
```

このほかに `Red-Stone: 44c499a0 ->`（右辺が空）が 1 件出ますが、
これは**テーマが古いのではなく、上のスクリプトがブランチを特定できなかった**ケースです。
homepage が `tree/Red-Stone` なのに実ブランチが `Red_Stone` のため、
`refs/heads/Red-Stone` の問い合わせが空を返しています
（実ブランチで引き直すと pin は最新と一致します）。
**「homepage をブランチ名の情報源にできない」ことの実例**なので、下の直し方の根拠になります。

**直し方**: 「`rev` の形で分岐する」のをやめるのが本質ですが、
**それだけでは直りません。追跡先の情報がどこにも保持されていない**のが本当の欠落です。

テーマの配布元は 2 種類に分かれます。

| 形 | 追跡先 | 件数 |
|---|---|---|
| テーマ専用リポジトリ（`rishav12s/Rain-Dark` など） | デフォルトブランチ | 37 |
| 1 リポジトリをブランチで分割（`HyDE-Project/hyde-themes`、`hyde-gallery`、`mahaveergurjar/Theme-Gallery`、`RAprogramm/HyDe-Themes`） | 個別のブランチ | 21 |

後者のブランチ名は `meta.homepage` の `/tree/<ブランチ>` に事実上書かれているだけで、
機械可読な形では持っていません。しかもその homepage が信用できないケースがあります。

- [`Red-Stone.nix`](../pkgs/hydenix-themes/Red-Stone.nix) → homepage は `tree/Red-Stone` だが、実ブランチは **`Red_Stone`**（アンダースコア）
- [`Mac-OS.nix`](../pkgs/hydenix-themes/Mac-OS.nix) → homepage は `tree/Mac-Os`（大文字小文字が不一致）

スクリプトが `NAME=$(basename "$NIX_FILE" .nix)` を計算しているのに
`echo` 以外で使っていないのは、当初「ファイル名＝ブランチ名」を想定していた名残に見えますが、
上記のとおりその前提も成り立ちません。

したがって修正は次の 2 段構えになります。

1. 各テーマファイルに追跡先を明示するフィールドを足す

   ```diff
    src = pkgs.fetchFromGitHub {
      owner = "mahaveergurjar";
      repo = "Theme-Gallery";
   +  ref = "Red_Stone";        # 専用リポジトリなら "main" / "master"
      rev = "44c499a0...";
   ```

   `ref` は `fetchFromGitHub` に渡さず、更新スクリプトだけが読むメタ情報として扱います
   （`mkTheme` 側で受け取って捨てるか、`src` の外に置く）。

2. スクリプトを「常に `git ls-remote <url> <ref>` で解決 → 変われば `rev` と `sha256` の両方を書き換える」形に直す。
   `rev` の形を見る分岐（L28-42）は丸ごと不要になります。

あわせて、workflow の PR 本文
（`This PR updates the sha256 for HyDE themes based on their specified rev.`）と
[05-theme-system.md](./05-theme-system.md) の
「`sha256` は …… が定期的に更新します」という記述も実態に合わせる必要があります。

**付随して直すとよい点**:

- [`update-themes.sh`](../scripts/update-themes.sh) L13-16 の `grep -oP` は GNU grep 依存で、
  `nix-shell -p` の指定に GNU grep が入っていないため **macOS ローカルでは動きません**
  （CI の ubuntu では通るので表面化していない）。`sed -E` で代替するか `gnugrep` を足す
- L51 の `nix hash convert --hash-algo sha256` と L67 の `nix hash to-sri --type sha256` が不統一
  （出力はどちらも SRI なので実害は無い。`nix hash to-sri` は deprecated）

**優先度の補足**: ビルドは壊れないので B に置いていますが、
**「自動化が存在するのに機能していない」という点では A 相当の危うさ**があります。
上流にもそのまま存在する問題なので、PR を送る価値があります。

### B-8. `setThemeDconf.service` が存在しないスクリプトを起動している

**問題**: テーマ適用 3 段構えの【2 段目】が、**実在しないファイル**を指しています。

```nix
# modules/hm/theme.nix:184
ExecStart = ''
  ${config.home.homeDirectory}/.local/lib/hyde/dconf.set.sh
'';
```

現在ピン留めしている HyDE に `dconf.set.sh` はありません。
上流のリファクタリングで `color/dconf.sh` へ移動・改名されています。
TODO 中の `theme.set.sh` も同様に消えています（`color.set.sh` が相当）。

**確認方法**: ピン留め中の rev に対して 3 つのパスの有無を引きます。

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

**実害**: 見た目ほど大きくありません。**dconf 設定自体は別経路で当たっています。**

`theme.switch.sh` の末尾が `wallpaper.sh` を呼び、`wallpaper/core.sh` が
`color.set.sh` をバックグラウンド実行し、その `color.set.sh` が
`load_dconf_kdeglobals()` の中で `color/dconf.sh` を source するためです。

つまり【2 段目】は**丸ごと死んでいるが、【3 段目】が同じ仕事を内包している**ので、
結果として破綻していません。残るのは次の 2 点です。

- `systemctl --user --failed` に常時 1 件出る（セッションが degraded 扱いになる）
- `After = ["setThemeDconf.service"]` の順序制約が意味を失っている

**直し方**: **サービスごと削除する**のが妥当です。
`setTheme.service` の `After` からも該当行を外します。

> [!WARNING]
> **パスを `color/dconf.sh` に差し替えるだけでは直りません。**
> このスクリプトは `color.set.sh` から source される前提で書かれており、
> 単体起動では `dcol_mode` が未設定になります。
> 先頭の `COLOR_SCHEME="prefer-$dcol_mode"` が `"prefer-"` という
> 壊れた値になるため、かえって悪化します。
> `color.set.sh` を直接呼ぶ手もありますが、引数に現在の壁紙パスが要るため、
> サービス側でそれを解決する処理が新たに必要になります。

**優先度の補足**: 壊れて見えるわりに実害が小さいので B に置いています。
根本的には「HyDE のスクリプト名を Nix 側にハードコードしている」ことが原因で、
これは C-1 で扱う設計課題そのものの実例です。

---

## C. 優先度: 低（仕様として割り切れるもの）

| 項目 | 内容 | 確認方法 | 対応の方向性 |
|---|---|---|---|
| **`pyprland` が使えない** | 本家 issue #188（`hyde-shell pypr console` が動かない）が未解決。フォークでは imports もオプションも削除済み | `grep -rn "pyprland" modules/` → コメントアウト行しか出ない | 上流の HyDE 側の問題。scratchpad が欲しくなったら再検討 |
| **`nix`/`sddm`/`system` が `enable` に従わない** | `default = true` 固定（[07-5](./07-reading-notes.md)） | `grep -rn "default = config.hydenix.enable\|default = true;" modules/system/*.nix` → `nix.nix` / `sddm.nix` / `system.nix` だけが `true` 固定 | `config.hydenix.enable` に揃えるべきだが、既存利用者の環境が変わるので慎重に |
| **履歴の環境変数が `xdg.nix` にある** | 本家 issue #154 | `grep -n "HIST" modules/hm/xdg.nix` → `HISTFILE` / `HISTSIZE` / `SAVEHIST` が出る | `shell.nix` へ移す。一貫性の問題のみ |
| **fish の `$aurhelper` エイリアス** | Arch の名残で NixOS では動かない | `grep -rn "aurhelper" modules/` → `shell.nix` に 4 つのエイリアス。実機では `un` を打つと空変数で失敗する | 削除するか NixOS 版に置換 |
| **`.config/waybar/modules` を配置している** | 本家 TODO の「もう配置不要では」が残存 | `grep -rn "waybar/modules" modules/` → `waybar.nix` と `hyde.nix` の 2 か所で配置 | 実機で外して試さないと判断できない |
| **hyprlock が `hyprland/` の外にある** | `lockscreen.nix` のまま。hyprlock と swaylock の排他 assertion も無い | `ls modules/hm/hyprland/ modules/hm/lockscreen.nix` で配置を見る | 設計上の課題。統合するなら大きめの変更 |
| **`hyde config.toml` がオプション化されていない** | mutable なので手で編集するしかない | `grep -n -A4 '".config/hyde/config.toml"' modules/hm/hyde.nix` → `source` + `mutable = true` のみ | Nix オプション化は大仕事。効果も限定的 |
| **`kdePackages.kconfig` の要否** | コード中に TODO が残っている | `grep -n "kconfig" modules/hm/hyde.nix` → TODO コメント付きで残っている | 外して動くか実機で確認するだけ |
| **GTK テーマ初回変更時のちらつき** | `gtk.nix` に TODO | `grep -n "TODO" modules/hm/gtk.nix`。再現は実機でテーマを切り替えるしかない | 原因不明。優先度低 |
| **spicetify 対応** | `spotify.nix` に TODO | `grep -n "TODO" modules/hm/spotify.nix` → 案のコメントだけで実装は無い | flatpak 前提の案が書かれているだけ |
| **本家 issue #182: hypr windowrules errors** | 状態不明。HyDE の bump で解消した可能性あり | 実機で `hyprctl configerrors`（何も出なければ解消済み） | まず再現するか確認 |

### C-1. テーマ適用を Nix 側で再現する（`theme.nix` の TODO）

[`modules/hm/theme.nix`](../modules/hm/theme.nix) に残っている TODO の検討です。

> `#TODO: this works but a more robust implementation is possible. just do what
> theme.set.sh/dconf.set.sh does and use home.file to set the correct gtk/qt/etc options`

実現すれば activation script も systemd サービスも mutable ファイルも減らせます。
ただし**そのまま実行することはできません**。理由を先に 2 つ挙げます。

1. **TODO が名指ししている 2 本のスクリプトは、もう存在しません**（B-8）。
   現在の相当物は `theme.switch.sh` と `color.set.sh` / `color/dconf.sh` です。
   TODO を書いた時点の HyDE と現在の HyDE では構造が変わっています。
2. **「一部だけ Nix 化する」ができません**。後述の「なぜ中途半端にできないのか」を参照。

#### 何を Nix 化できるのか

`theme.switch.sh` がやっていることは、**静的**（選んだテーマ名だけで決まる）と
**動的**（現在の壁紙に依存する）にきれいに二分できます。

**静的 — `theme.active` が決まれば内容が確定する。ビルド時に生成可能**

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

**動的 — 現在の壁紙に依存する。実行時に生成するしかない**

- wallbash の色生成一式（`hypr/themes/colors.conf`, `waybar/theme.css`,
  `kitty/theme.conf`, `dunst/dunstrc`, `rofi/theme.rasi`, Kvantum, VS Code …）
- 壁紙そのものの適用（`wallpaper.sh`）
- `qt5ct/colors/wallbash.conf` など wallbash 由来の配色ファイル

**したがって TODO は「静的な側だけ」なら実現可能で、動的な側は残ります。**
mutable ファイルを全廃できるわけではない、というのが最初に押さえるべき点です。

#### なぜ中途半端にできないのか

上の表の**静的な生成先はすべて `theme.switch.sh` も書きに来ます**。
Nix が `settings.ini` を store へのシンボリックリンクとして置くと、
`toml_write` が読み取り専用のリンク先に書こうとして失敗します。

つまり Nix 側で書くなら、**`theme.switch.sh` の静的な部分を呼ばないようにする**必要があります。
HyDE にそれを止めるフラグはないので、取れる道は次の 3 つです。

| 案 | 内容 | 評価 |
|---|---|---|
| 1 | `theme.switch.sh` を呼ぶのをやめ、動的な側（`wallpaper.sh`）だけ直接呼ぶ | **本命**。下で詳述 |
| 2 | `pkgs/hyde` で `theme.switch.sh` にパッチを当てて静的部分を削る | 非推奨。行番号決め打ちの `sed` は既に一度失敗して[コメントアウト済み](../pkgs/hyde/default.nix)（`sed -i '187,190d'`） |
| 3 | mutable のまま両方に書かせる | 現状。何も得られない |

案 1 は、`theme.switch.sh` の末尾がやっていることをそのまま引き継ぐ形になります。

```bash
# theme.switch.sh:239 — 動的な側の入口はここ 1 行
"$LIB_DIR/hyde/wallpaper.sh" -s "$(readlink "$HYDE_THEME_DIR/wall.set")" --global
```

ただし `wallpaper.sh` は `HYDE_THEME` と `HYDE_THEME_DIR` が設定済みであることを前提にしています。
`theme.switch.sh:121` の `set_conf "HYDE_THEME" "$themeSet"` と、
`globalcontrol.sh` / `env-theme` の読み込みに相当する処理は Nix 側で用意する必要があります。

#### 設計上の分岐点: テーマのメタデータをどこから取るか

静的な側を生成するには `GTK_THEME` / `ICON_THEME` / `CURSOR_THEME` / フォント名を知る必要があります。
これらの出どころはテーマパッケージ内の `hypr.theme` です。

```bash
# 例: Catppuccin Macchiato
$GTK_THEME=Catppuccin-Macchiato
$ICON_THEME = Tela-circle-dracula
$COLOR_SCHEME = prefer-dark
```

**書かれていない変数は [`Configs/.local/share/hyde/env-theme`](https://github.com/HyDE-Project/HyDE/blob/master/Configs/.local/share/hyde/env-theme) の既定値にフォールバックします。**
上の例のようにテーマ側は 3 つしか上書きしないことが多いので、
テーマごとに持つべきデータは実際には少数です。実際の分布は次で数えられます。

```bash
# 実機で。各テーマの hypr.theme が上書きしている変数を集計する
grep -h '^\$' ~/.config/hyde/themes/*/hypr.theme \
  | sed 's/ *=.*//' | sort | uniq -c | sort -rn
```

取りうる実装は 3 つあります。

| 案 | 方法 | 判定 |
|---|---|---|
| A | eval 時に `builtins.readFile "${themePkg}/…/hypr.theme"` で読む | **不可**。IFD になる |
| B | `runCommand` の中で `hypr.theme` を読んで設定ファイルを生成する | 可。ただし値が Nix から見えない |
| C | 各テーマの `.nix` にメタデータを宣言する | **推奨** |

**案 A が使えない理由**: テーマパッケージは derivation です。
その出力を eval 時に `readFile` すると import-from-derivation になり、
評価のたびにテーマのビルドが走ります。`nix flake check` や CI の eval が重くなり、
`--no-allow-import-from-derivation` では落ちます。

なお「パスが eval 時に分かること」自体は問題ありません。ビルドを伴わずに解決できます。

```bash
nix eval --impure --raw --expr '
  let hc = (builtins.getFlake (toString ./.)).homeConfigurations.default;
  in hc.config.home.file.".config/hyde/themes/Catppuccin Mocha".source'
# => /nix/store/…-Catppuccin-Mocha/share/hyde/themes/Catppuccin Mocha
```

問題になるのは**中身を読む**ときだけです。

**案 B**: `pkgs.runCommand` の中で `hypr.theme` を `sed` / `hyq` で解析し、
`settings.ini` などを出力するディレクトリを作って `home.file.….source` に渡します。
IFD にはならず、58 テーマ分のデータ入力も不要です。
ただし値が Nix の世界に出てこないため、home-manager の
`dconf.settings` / `gtk.*` / `qt.*` といった既存モジュールには載せられず、
利用者が個別の値を上書きすることもできません。

**案 C（推奨）**: テーマ定義そのものに書きます。

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

こうすると値が eval 時に見えるので、**hydenix が設定ファイルを手書きする必要がなくなります**。
home-manager の `gtk` / `qt` / `dconf` モジュールがすでに
`settings.ini` / `.gtkrc-2.0` / dconf の書き方を知っているので、そちらに委譲できます。
これが本当の利得で、案 B では得られません。

58 ファイルへの手入力が要るように見えますが、`hypr.theme` から値を抽出して
`.nix` を生成するスクリプトを書けば済みます。
**B-7 の修正が同じ 58 ファイルに `ref` を足す作業なので、まとめてやるのが効率的です。**
上流のテーマが値を変えたときに備えて、抽出結果と `.nix` の差分を CI で検出する仕組みも
同時に入れておくとよいでしょう。

#### 段階的な進め方

1. **B-8 を先に片付ける**（死んだサービスの削除）。単独で価値があり、依存もありません
2. テーマ定義に `settings` を足し、抽出スクリプトと CI の drift 検出を用意する（案 C）
3. dconf だけ home-manager の `dconf.settings` に移す。
   `setThemeDconf.service` が不要になり、3 段構えが 2 段になります
4. GTK / Qt / カーソルを `gtk.*` / `qt.*` と `home.file` に移し、対応する mutable 指定を外す
5. `theme.switch.sh` の呼び出しを `wallpaper.sh` の直接呼び出しに置き換える（案 1）

3 まで進めた時点で「初回 rebuild で dconf が失敗する」問題は消えるはずです。
home-manager の dconf モジュールは D-Bus セッションが無い場合の面倒を自前で見ますが、
**activation 時の挙動は実機で確認してください**（`journalctl --user` と
`dconf dump /org/gnome/desktop/interface`）。ここは未検証です。

#### 効果と費用

**得られるもの**:

- 3 段構えの適用が減り、初回 rebuild の失敗が消える
- テーマ設定が Nix の世界に入るので、利用者が普通の home-manager オプションで上書きできる
- dry-activate が正しく動くようになる（A-2 にも効く）

**失うもの・費用**:

- **上流追従コストが上がります。** `theme.switch.sh` が変わるたびに Nix 側の再現も追う必要があります。
  この危険は仮定の話ではなく、**`dconf.set.sh` → `color/dconf.sh` の改名に追従できていない
  B-8 が実例**です。
  HyDE のスクリプトを呼ぶだけなら改名は追従不要でした。
- **A-3 の解決にはなりません。** 減らせるのは上の表の十数件で、
  mutable ファイル 115 件の大半は wallbash 由来のため残ります。
- 実機での検証が必須です。GTK4・Qt・カーソルは壊れても気づきにくい割に、
  壊れたときの体感は悪い部類です。

**結論**: 設計としては正しい方向ですが、**費用に対する効果が限定的**です。
「HyDE のスクリプトをそのまま動かす」という現在の方針を捨てて
hydenix がテーマ適用を自前で持つ、という方針転換を伴うので、
**着手するなら上流に issue を立てて合意を取ってからにすべきです。**
一方、段階 1（B-8）と段階 3（dconf のみ）は方針転換を伴わず単独で価値があるため、
そこだけ先に進めるのは十分に現実的です。

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
