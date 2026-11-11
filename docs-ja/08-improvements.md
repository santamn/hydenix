# 08. 将来加えると良い変更

直したほうがよいと判断した箇所の一覧です。上のものほど優先度が高く、下にいくほど仕様として割り切れるものになります。各項目は問題・原因・確認方法・修正方法の順に並べ、実害やリスクを別に述べたい項目には、その節を挟んでいます。指摘を鵜呑みにせず、まず手元で実行して再現してみてください。

---

## 確認方法の共通手順

確認には 2 種類あります。

| 種類 | 内容 |
|-----|------|
| `grep` で足りるもの | コードの形を見れば分かる（書き間違い・書き漏らし） |
| `nix eval` が要るもの | 実際に評価するとどうなるかを見る必要がある |

`nix eval` を使う項目はリポジトリのルートで実行してください。`/etc/nix/nix.conf` に `experimental-features = nix-command flakes` が入っている前提です（hydenix / NixOS 環境では最初から有効。無ければ `--extra-experimental-features 'nix-command flakes'` を足す）。

ほとんどの確認は flake の `homeConfigurations.default` を評価するだけで、ビルドとアクティベーションは行いません。初回は依存 flake の取得で数分かかりますが、2 回目以降は数秒です。

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

現在、この優先度の項目はありません。

---

## B. 優先度: 中

現在、この優先度の項目はありません。

---

## C. 優先度: 低（仕様として割り切れるもの）

| 項目 | 内容 | 確認方法 | 対応の方向性 |
|---|---|---|---|
| `pyprland` が使えない | 本家 issue #188（`hyde-shell pypr console` が動かない）が未解決。このフォークは pyprland のパッケージも設定も配置しない | `grep -rn "pyprland" modules/` → 何も出ない | 上流の HyDE 側の問題。scratchpad が欲しくなったら再検討 |
| waybar モジュールが NixOS で動くか未確認 | `waybar.nix` に TODO（review waybar modules for nix compatibility）が残っている。ビルド時に生成する `includes.json` が `~/.config/waybar/modules` のモジュール定義を 42 件読み込むので、配置そのものは外せない | `grep -n "TODO" modules/hm/waybar.nix`。読み込まれるモジュールの一覧は `nix build .#checks.x86_64-linux.waybar-includes` の出力で見られる | `waybar.nix` のコメントどおり NixOS で動かないものが混じっている可能性があるので、1 つずつ実機で確かめる |
| `hyde config.toml` がオプション化されていない | mutable なので手で編集するしかない | `grep -n -A4 '".config/hyde/config.toml"' modules/hm/hyde.nix` → `source` / `force` / `mutable = true` だけ | Nix オプション化は大仕事。効果も限定的 |
| `kdePackages.kconfig` の要否 | コード中に TODO が残っている | `grep -n "kconfig" modules/hm/hyde.nix` → TODO コメント付きで残っている | 外して動くか実機で確認するだけ |
| GTK テーマ初回変更時のちらつき | `gtk.nix` に TODO | `grep -n "TODO" modules/hm/gtk.nix`。再現は実機でテーマを切り替えるしかない | 原因不明。優先度低 |
| spicetify 対応 | `spotify.nix` に TODO | `grep -n "TODO" modules/hm/spotify.nix` → 案のコメントだけで実装は無い | flatpak 前提の案が書かれているだけ |

### C-1. テーマ適用を Nix 側で再現する（`theme.nix` の TODO）

[`modules/hm/theme.nix`](../modules/hm/theme.nix) に残っている TODO の検討です。

> `#TODO: this works but a more robust implementation is possible. just do what color.set.sh/color/dconf.lua does and use home.file to set the correct gtk/qt/etc options`

実現すれば activation script、systemd サービス、mutable ファイルをいずれも減らせます。ただし、そのままでは実行できません。理由を先に 2 つ挙げます。

1. TODO が名指ししている 2 本のスクリプトをなぞっても、静的な設定の大半は取りこぼす。`color.set.sh` は壁紙から配色を作る動的な側の本体で、`color/dconf.lua` が書くのは dconf だけである。GTK / Qt / カーソルの設定ファイルを書いているのは `theme.switch.sh` 自身である。
2. 一部だけを Nix 化する、という進め方はとれない。後述の「なぜ中途半端にできないのか」を参照。

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
| `~/.local/state/hyde/lua_state/hypr_theme.lua` | `theme.switch.sh`（`hyq --dump … --export lua`） | `hypr.theme` を Hyprland の Lua 設定に変換したもの |
| dconf（`org/gnome/desktop/interface` ほか） | `color/dconf.lua`（icon-theme は `theme.switch.sh` も `dconf write` で書く） | GTK / icon / cursor / font / color-scheme |

動的な側は現在の壁紙に依存するので、実行時に生成するしかありません。

- wallbash の色生成一式（`hypr/themes/colors.conf`, `waybar/theme.css`, `kitty/theme.conf`, `dunst/dunstrc`, `rofi/theme.rasi`, Kvantum, VS Code …）
- 壁紙そのものの適用（`wallpaper.sh`）
- `qt5ct/colors/wallbash.conf` など wallbash 由来の配色ファイル

したがって TODO は静的な側だけなら実現可能で、動的な側は残ります。mutable ファイルを全廃できるわけではない、というのが最初に押さえるべき点です。

#### なぜ中途半端にできないのか

上の表の静的な生成先は、どれも `theme.switch.sh` かそこから呼ばれるスクリプトが書きに来ます。Nix が `settings.ini` を store へのシンボリックリンクとして置くと、`toml_write` が読み取り専用のリンク先に書こうとして失敗します。

つまり Nix 側で書くなら、`theme.switch.sh` の静的な部分を呼ばないようにしなければなりません。HyDE にそれを止めるフラグはないので、取れる道は次の 3 つです。

| 案 | 内容 | 評価 |
|---|---|---|
| 1 | `theme.switch.sh` を呼ぶのをやめ、動的な側（`wallpaper.sh`）だけ直接呼ぶ | 本命。下で詳述 |
| 2 | `pkgs/hyde` で `theme.switch.sh` にパッチを当てて静的部分を削る | 非推奨。静的な部分は `theme.switch.sh` の L103〜217 にまたがり、AGENTS.md の決まりどおり `substituteInPlace --replace-fail` で削ると、HyDE がこの範囲を変えるたびにビルドが止まる |
| 3 | mutable のまま両方に書かせる | 現状。何も得られない |

案 1 は、`theme.switch.sh` の末尾がやっていることをそのまま引き継ぐ形になります。動的な側を受け持つのは L232〜276 で、テーマの壁紙を決めて `wallpaper.sh` を呼び、配色の出力が揃っていなければ `color.set.sh` を直接呼び直します。

```bash
# theme.switch.sh:232-276 から抜粋
theme_wallpaper="$(readlink "$HYDE_THEME_DIR/wall.set")"
…
    "$LIB_DIR/hyde/wallpaper.sh" -s "$theme_wallpaper" --global || wallpaper_status=$?
…
if ! wallbash_state_is_complete; then
    print_log -sec "theme" -stat "colours" "generating the colour state for $HYDE_THEME"
    if ! "$LIB_DIR/hyde/color.set.sh" "$theme_wallpaper"; then
```

ただし `wallpaper.sh` は `HYDE_THEME` と `HYDE_THEME_DIR` が設定済みであることを前提にしています。`theme.switch.sh:98` の `set_conf "HYDE_THEME" "$themeSet"` と、L101-102 の `globalcontrol.sh` / `env-theme` の読み込みに相当する処理は Nix 側で用意しなければなりません。

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

案 A が使えないのは、テーマパッケージが derivation だからです。その出力を eval 時に `readFile` すると import-from-derivation になり、評価のたびにテーマがビルドされます。`nix flake check` や CI の eval が重くなり、`--no-allow-import-from-derivation` では落ちます。

なお、パスが eval 時に分かること自体は問題ありません。ビルドを伴わずに解決できます。

```bash
nix eval --impure --raw --expr '
  let hc = (builtins.getFlake (toString ./.)).homeConfigurations.default;
  in hc.config.home.file.".config/hyde/themes/Catppuccin Mocha".source'
# => /nix/store/…-Catppuccin-Mocha/share/hyde/themes/Catppuccin Mocha
```

問題になるのは中身を読むときだけです。

案 B は、`pkgs.runCommand` の中で `hypr.theme` を `sed` / `hyq` で解析し、`settings.ini` などを出力するディレクトリを作って `home.file.….source` に渡すものです。IFD にはならず、58 テーマ分のデータ入力も不要です。ただし値が Nix の世界に出てこないため、home-manager の `dconf.settings` / `gtk.*` / `qt.*` といった既存モジュールには載せられず、利用者による個別の値の上書きもできません。

案 C はテーマ定義そのものに書く方法で、これを推奨します。

```nix
# pkgs/hydenix-themes/Catppuccin-Macchiato.nix
mkTheme rec {
  name = "Catppuccin-Macchiato";
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

58 ファイルへの手入力が要るように見えますが、`hypr.theme` から値を抽出して `.nix` を生成するスクリプトを書けば済みます。上流のテーマが値を変えたときに備えて、抽出結果と `.nix` の差分を CI で検出する仕組みも同時に入れておくとよいでしょう。

#### 段階的な進め方

1. テーマ定義に `settings` を足し、抽出スクリプトと CI の drift 検出を用意する（案 C）
2. dconf だけ home-manager の `dconf.settings` に移す。ログイン後の `setTheme.service` で dconf の取りこぼしを直す必要がなくなる
3. GTK / Qt / カーソルを `gtk.*` / `qt.*` と `home.file` に移し、対応する mutable 指定を外す
4. `theme.switch.sh` の呼び出しを `wallpaper.sh` の直接呼び出しに置き換える（案 1）

2 まで進めた時点で、初回 rebuild でも dconf の値は home-manager が書くので、取りこぼしは無くなるはずです。home-manager の dconf モジュールは D-Bus セッションが無い場合の面倒を自前で見ますが、activation 時の挙動は実機で確認してください（`journalctl --user` と `dconf dump /org/gnome/desktop/interface`）。ここは未検証です。

#### 効果と費用

得られるものは 2 つです。

- 2 段構えの適用が減り、初回 rebuild での dconf の取りこぼしが消える
- テーマ設定が Nix の世界に入るので、利用者が普通の home-manager オプションで上書きできる

失うもの・費用は次のとおりです。

- 上流追従コストが上がる。`theme.switch.sh` が変わるたびに Nix 側の再現も追う必要がある。この危険は仮定の話ではない。HyDE は dconf を書くスクリプトを `dconf.set.sh` から `color/dconf.sh`、さらに `color/dconf.lua` へと移しており、Nix 側で再現していればそのたびに追従が要った。HyDE のスクリプトを呼ぶだけなら、こうした改名に追従する必要はない。
- mutable ファイルの大半は残る。上の表の生成先で mutable なのは `settings.ini`、`.gtkrc-2.0`、`xsettingsd.conf`、`kdeglobals`、`index.theme` の 5 件だけで、デモ構成（`homeConfigurations.default`）の mutable ファイル 106 件のうち残りは、テーマ 58 個の配置先や wallbash の出力先などである。
- 実機での検証が必須である。GTK4・Qt・カーソルは不具合が出ても気づきにくい割に、出たときの体感は悪い部類である。

結論として、設計としては正しい方向ですが、費用に対する効果が限定的です。HyDE のスクリプトをそのまま動かすという現在の方針を捨てて hydenix がテーマ適用を自前で持つ、という方針転換を伴うので、着手するなら issue に判断の理由を残してからにすべきです。一方、段階 2（dconf のみ）は方針転換を伴わず単独で価値があるため、そこだけ先に進めるのは十分に現実的です。

---

## D. 利用側で持てばよいもの

hydenix に無くても、利用側の設定で解決できるものです。hydenix 側では扱いません。

| 項目 | 対応 |
|---|---|
| `nh` によるガベージコレクト | 利用側の NixOS 設定で持つ |
| nixos-anywhere / disko 対応 | 利用側で導入する |
| 多ホスト構成 | 利用側で組む。hydenix と両立する |
