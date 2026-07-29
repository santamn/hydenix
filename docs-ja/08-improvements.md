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
