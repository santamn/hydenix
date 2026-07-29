# 02. このリポジトリを読むための Nix 入門

Nix 言語の網羅的な入門ではなく、**hydenix のコードに実際に出てくるもの**に絞って説明します。

## 1. Nix 言語の最低限

### 属性集合 (attribute set)

JSON のオブジェクトに相当します。Nix の設定はほぼ全部これです。

```nix
{
  name = "hydenix";
  version = 1;
  nested = {a = 1; b = 2;};
  nested.c = 3;          # ドット記法でネストを書ける（上の nested とマージされる）
}
```

> **同じパスに 2 回代入するとどうなる？**
> 両辺が属性集合リテラルなら自動でマージされます。
> `modules/hm/rofi.nix` に `home.file = {...}` が 2 回出てくるのはこのためです。
> 値がリテラルでない場合（例: `a = 1; a = 2;`）はエラーになります。
> なお `treefmt.nix` で statix の `repeated_keys` lint を無効化しているのも、
> この書き方が随所にあるためです。

### 関数

引数は 1 つだけです。複数渡したいときは属性集合を使うか、カリー化します。

```nix
# 属性集合を受け取る形（モジュールはすべてこの形）
{config, lib, pkgs, ...}: {...}
#                  ↑ 「他の引数も来るかもしれないが無視する」の意味。これが無いとエラーになる

# カリー化（pkgs/hydenix-themes/utils/mkTheme.nix がこの形）
{pkgs}: {name, src, meta}: <derivation>
#  ↑先に pkgs を渡して関数を作り、後からテーマ情報を渡す

# 二重カリー化（modules/hm/hyprland/utils/mkHyprConfig.nix）
{config, pkgs, lib, ...}: {name, extension ? "conf"}: <モジュール>
#  ↑ import 時に前半を渡し、imports の中で後半を渡す。返り値がモジュールになる
```

`?` は既定値付き引数です。`extension ? "conf"` は「省略時は `"conf"`」の意味。

### let ... in

ローカル変数の定義です。

```nix
let
  cfg = config.hydenix.hm.theme;   # 長い名前の短縮。全モジュール共通の慣用句
in {... cfg.active ...}
```

### 文字列と補間

```nix
"通常の文字列"
''
  複数行文字列。インデントは自動で揃えられる
''
"${pkgs.hyde}/Configs/.config/hypr/hyprland.conf"   # ${...} で値を埋め込む
```

`${pkgs.hyde}` は評価すると `/nix/store/xxxx-hyde` のような**パス文字列**になります。
つまり「HyDE パッケージの中のこのファイル」を指しているわけです。

> [!WARNING]
> **`''` 文字列の中では `#` はコメントになりません。** ただの文字です。
> そして `${...}` は文字列内でも補間されます。
> つまり `buildPhase = ''...''` の中に説明を書くときは、
> `${` と `''` を含めてはいけません（含めると補間されるか、文字列が途中で終わります）。
> 文字として書きたい場合は `''${...}` / `'''` とエスケープします
> （`modules/hm/shell.nix` の p10k 設定に実例があります）。

### 演算子

| 演算子 | 意味 | 例 |
|---|---|---|
| `//` | 属性集合の上書きマージ | `hyprlandPkgs // (import ./pkgs final prev)` |
| `?` | その属性が存在するか | `if cfg.animations.overrides ? ${preset} then ... else ...` |
| `or` | 属性が無いときの既定値 | `pkgs.hydenix-themes.${name} or null` |
| `++` | リストの連結 | `[a] ++ lib.optionals cond [b]` |

> **注意**: `or` は**論理和ではありません**。属性選択とセットでしか使えません。
> `modules/hm/editors.nix` の `cfg.vim or cfg.neovim` は
> 「`cfg.vim` を取り出し、無ければ `cfg.neovim`」の意味で、実質 `cfg.vim` だけを見ています。

### rec

属性集合の中で自分の属性を参照できるようにします。

```nix
buildGoModule rec {
  version = "0.5.2";
  src = fetchFromGitHub {rev = "v${version}"; ...};   # ← 上の version を参照できる
}
```

## 2. モジュールシステム

NixOS / home-manager の設定は「モジュール」の集合体です。モジュールは次の 3 つを持ちます。

```nix
{
  imports = [...];   # 取り込む他のモジュール
  options = {...};   # 「こういう設定項目があります」という宣言
  config  = {...};   # 実際に適用する設定値
}
```

### options: 設定項目の宣言

```nix
options.hydenix.hm.theme = {
  active = lib.mkOption {
    type = lib.types.str;              # 型（間違った型を入れるとビルドが止まる）
    default = "Catppuccin Mocha";      # 既定値
    description = "Active theme name"; # 説明（ドキュメント生成に使われる）
  };
};
```

よく使う型:

| 型 | 意味 |
|---|---|
| `lib.types.bool` / `str` / `int` | 真偽値 / 文字列 / 整数 |
| `lib.types.lines` | 複数行文字列。複数モジュールが書くと**連結**される |
| `lib.types.listOf X` | X のリスト。複数モジュールが書くと**連結**される |
| `lib.types.attrsOf X` | 「名前 → X」の属性集合 |
| `lib.types.nullOr X` | X または null（「未指定」を表現したいとき） |
| `lib.types.enum ["a" "b"]` | 決められた値のどれか |
| `lib.types.submodule {...}` | 入れ子の設定オブジェクト |
| `lib.types.addCheck T pred` | 既存の型に追加の検査を足す |

`addCheck` は `modules/system/default.nix` の timezone 型で使われています
（「空白を含まない文字列」という制約を足している）。

### config: 設定値の適用

**同じオプションを複数のモジュールが書いても衝突しません。** 型に応じてマージされます。

- リスト → 連結される（だから各モジュールが自由に `environment.systemPackages` に足せる）
- 属性集合 → マージされる
- 単一の値 → 衝突するとエラー（優先度を付けて解決する）

### 優先度を操る関数

| 関数 | 意味 | 使いどころ |
|---|---|---|
| `lib.mkDefault v` | 弱い既定値（利用者の指定が必ず勝つ） | `hydenix.enable = lib.mkDefault false;` |
| `lib.mkForce v` | 強制（他を無視して必ずこの値） | 上書きしたいとき |
| `lib.mkIf cond {...}` | 条件が偽ならブロックごと無効化 | `config = lib.mkIf cfg.enable {...};` |
| `lib.mkMerge [a b]` | 複数の設定を統合 | 条件分岐した設定をまとめるとき |
| `lib.mkOrder n v` | 順序の指定 | `.zshrc` の書き込み位置制御 |

`mkIf` が重要な理由: 単に `if cond then {...} else {}` と書くと、
条件の評価に `config` が必要な場合に**無限再帰**に陥ることがあります。
`mkIf` は評価を遅延させるので安全です。

`mkDefault` の有無は運用に直結します。このフォークでは
`networking.hostName` / `time.timeZone` / `i18n.defaultLocale` に `mkDefault` が付いたため、
利用者側の指定が素直に優先されるようになりました。
一方 `system.stateVersion` / `home.stateVersion` には付いていないので、
**利用者が別の値を書くと定義衝突でビルドが落ちます**（[08](./08-improvements.md) 参照）。

### assertions と warnings

```nix
assertions = [
  {assertion = cfg.hostname != ""; message = "hydenix.hostname must be set";}
];
warnings = ["設定を上書きしています"];
```

`assertion` が偽ならビルドが止まり、`message` が表示されます。
`modules/hm/hyprland/assertions.nix` が良い実例です。

## 3. このリポジトリで頻出する lib 関数

| 関数 | やること |
|---|---|
| `lib.mkEnableOption "説明"` | 既定値 false の bool オプションを作る短縮形 |
| `lib.optionals cond list` | 条件が真ならそのリスト、偽なら `[]` |
| `lib.optionalString cond str` | 条件が真ならその文字列、偽なら `""` |
| `lib.filter f list` | 条件に合う要素だけ残す |
| `lib.listToAttrs [{name=..;value=..;}]` | リストを属性集合に変換 |
| `lib.mapAttrs' f attrs` | 属性集合のキーと値を両方変換 |
| `lib.filterAttrs f attrs` | 属性集合を絞り込む |
| `lib.setAttrByPath ["a" "b"] v` | `{a.b = v;}` を作る |
| `lib.getAttrFromPath ["a" "b"] s` | `s.a.b` を取り出す |
| `lib.concatStringsSep ", " list` | 文字列リストを連結 |
| `lib.readFile path` | **ビルド時に**ファイルの中身を文字列として読む |
| `lib.escapeShellArg s` | シェルに安全に渡せるようクォートする |
| `lib.makeBinPath [pkgs...]` | パッケージのリストから `PATH` 用の文字列を作る |
| `lib.hm.dag.entryAfter ["X"] script` | activation script を X の後に実行する（home-manager 固有） |

`setAttrByPath` / `getAttrFromPath` は `modules/hm/mutable.nix` の核心部分です。
「`home.file` / `xdg.configFile` / `xdg.dataFile` の 3 つに同じ処理をする」ために、
属性パスをデータとして扱っています。

### `source` と `lib.readFile` の違い（重要）

```nix
# (A) リンクを張る：中身は変えられない
".config/hypr/hyprlock.conf".source = "${pkgs.hyde}/Configs/.config/hypr/hyprlock.conf";

# (B) 中身を読んで新しいファイルを生成：後ろに追記できる
".config/hypr/hypridle.conf".text = ''
  ${lib.readFile "${pkgs.hyde}/Configs/.config/hypr/hypridle.conf"}
  ${cfg.hypridle.extraConfig}
'';
```

`extraConfig` を提供しているモジュール（`mkHyprConfig` 生成分）が (B) を使っているのは、
この違いのためです。

## 4. パッケージのビルド

```nix
pkgs.stdenv.mkDerivation {
  name = "hyde";
  src = fetchFromGitHub {...};        # 入力（ソース）
  nativeBuildInputs = [...];          # ビルド時にだけ必要なツール
  buildInputs = [...];                # 実行時にもリンクされるライブラリ
  buildPhase = ''...'';               # ビルド処理
  installPhase = ''mkdir -p $out;'';  # $out に成果物を置く
}
```

`$out` が `/nix/store/<ハッシュ>-hyde` になります。
このディレクトリは**書き込み不可**であり、それが [04](./04-mutable-files.md) の話につながります。

`fetchFromGitHub` の `hash` / `sha256` は「内容のハッシュ」です。
改ざん検知と再現性のために必須で、値が合わないとビルドが失敗します
（`pkgs/hyde-gallery/default.nix` は空のままなのでビルドできません）。

## 5. overlay

```nix
final: _prev: {
  hyde = final.callPackage ./hyde {};
}
```

- `prev` … 上書き前の pkgs（他の overlay の影響を受けていない状態）
- `final` … すべての overlay 適用後の最終的な pkgs

返した属性が `pkgs` に足されるので、各モジュールから `pkgs.hyde` として使えるようになります。

`callPackage` は「定義ファイルの引数を自動で埋める」仕組みです。
`pkgs/pokego/default.nix` が `{lib, buildGoModule, fetchFromGitHub}:` という引数を
書けるのは、`callPackage` が pkgs から自動で探して渡してくれるからです。

`flake.nix` では Hyprland 側の overlay と合成しています。

```nix
overlays.default = final: prev:
  (inputs.hyprland.overlays.hyprland-packages final prev)
  // (import ./pkgs final prev);
```

`//` は上書きマージなので、名前が衝突したら `pkgs/` 側が勝ちます。

## 6. コードスタイル（このリポジトリの規約）

整形は **alejandra** に統一されており、CI で強制されます。

```bash
nix fmt          # treefmt 経由で alejandra / deadnix / statix が走る
```

alejandra は本家が使っていた nixfmt-rfc-style と見た目が違います
（`[ a b ]` ではなく `[a b]`、`{ x = 1; }` ではなく `{x = 1;}` など）。
本家のコードを参考にするときは整形差分に惑わされないでください。

## 7. 学習リソース

- [Nix Pills](https://nixos.org/guides/nix-pills/) — 仕組みを下から積み上げて理解したい人向け
- [nix.dev](https://nix.dev/) — 実用重視の公式チュートリアル
- [NixOS & Flakes Book（日本語訳あり）](https://nixos-and-flakes.thiscute.world/ja/) — flake 前提の解説
- [Nix 言語 1 時間チュートリアル](https://nix.dev/tutorials/nix-language) — 文法だけ手早く
- `nix repl` — 手を動かして確認するのが一番早いです
  ```
  nix repl
  nix-repl> :lf .          # このディレクトリの flake を読み込む
  nix-repl> outputs.nixosConfigurations.default.config.hydenix
  ```
