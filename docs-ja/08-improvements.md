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

3 つ目が本命ですが、ユーザーが手で編集した内容を消してよいかの判断が難しく、設計上の議論が必要です。大きめの変更なので、着手前に issue へ書き出して考えを固めたほうがよいでしょう。

---

## B. 優先度: 中

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

```text
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

```text
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

### B-10. 同名アイコンテーマを複数テーマが「異なる内容」で同梱している

#### 問題

HyDE テーマの tarball は各テーマリポジトリで別々の時期に生成されているため、同じアイコンテーマ（同じ `share/icons/<dir>`）を複数のテーマが**中身の違うビルド**で同梱していることがあります。全 58 テーマの pin 済み rev を調査して、内容が食い違うペアが 4 つ確認できました（10 桁は tar.gz の blob SHA）。

| 展開先ディレクトリ | テーマ A | テーマ B |
|---|---|---|
| `Tela-circle-grey` | Catppuccin Latte `1cd2add523` | Graphite Mono `1c9e602cc5` |
| `Tela-circle-green` | Greenify `1fbe03250f` | LimeFrenzy `6b38249179` |
| `Aretha-Dark-Icons` | Amethyst-Aura `a2933d8840` | Nightbrew `a936bb73d2` |
| `Gruvbox-Plus-Dark` | AbyssGreen `99ed823d5f` | Gruvbox Retro `e944ab8ae7` |

同名で blob も一致するペア（`TelaGreen` の Decay Green / Green Lush、`Vivid-Glassy-Dark` の Another World / Code Garden など）はバイト同一なので無害です。

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

`mkTheme` の `sharedAssets`（展開先ディレクトリ名 → 正準パッケージの attrset。該当ディレクトリを展開後に正準パッケージへの symlink に置き換える）がそのまま受け皿になります。ペアごとに正準ソースを 1 つ決めて登録するだけです。

| ディレクトリ | 正準ソース候補 |
|---|---|
| `Tela-circle-grey` / `Tela-circle-green` | nixpkgs `tela-circle-icon-theme.override { colorVariants = ["grey" / "green"]; }`（`Tela-circle-dracula` と同じ作り） |
| `Gruvbox-Plus-Dark` | nixpkgs `gruvbox-plus-icons`（展開先ディレクトリ名が一致するかは要確認） |
| `Aretha-Dark-Icons` | nixpkgs に無い。どちらかのテーマの blob を `fetchurl` で固定して 1 回だけ展開する小パッケージを作るか、原作者リポジトリから `fetchFromGitHub` する |

`sharedAssets` は「そのディレクトリを同梱していたテーマだけ」を置き換えるので、`home.packages` に増えるものはなく、該当テーマを有効にした人の閉包にだけ正準パッケージが入ります。あわせて `checks.theme-assets`（`buildEnv` はテーマを別 paths として突き合わせるので、`symlinkJoin` と違って同名衝突を検出できる）に該当テーマを足すと、正準化漏れが CI で落ちるようになります。

> 優先度は B の末尾（ビルドは壊れず、特定の組み合わせでしか起きない）。

---

## C. 優先度: 低（仕様として割り切れるもの）

| 項目 | 内容 | 確認方法 | 対応の方向性 |
|---|---|---|---|
| `pyprland` が使えない | 本家 issue #188（`hyde-shell pypr console` が動かない）が未解決。フォークでは imports もオプションも削除済み | `grep -rn "pyprland" modules/` → コメントアウト行しか出ない | 上流の HyDE 側の問題。scratchpad が欲しくなったら再検討 |
| `nix`/`sddm`/`system` が `enable` に従わない | `default = true` 固定（[07-4](./07-reading-notes.md)） | `grep -rn "default = config.hydenix.enable\|default = true;" modules/system/*.nix` → `nix.nix` / `sddm.nix` / `system.nix` だけが `true` 固定 | `config.hydenix.enable` に揃えるべきだが、既存利用者の環境が変わるので慎重に |
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

58 ファイルへの手入力が要るように見えますが、`hypr.theme` から値を抽出して `.nix` を生成するスクリプトを書けば済みます。上流のテーマが値を変えたときに備えて、抽出結果と `.nix` の差分を CI で検出する仕組みも同時に入れておくとよいでしょう。

#### 段階的な進め方

1. B-8 を先に片付ける（死んだサービスの削除）。単独で価値があり、依存もありません
2. テーマ定義に `settings` を足し、抽出スクリプトと CI の drift 検出を用意する（案 C）
3. dconf だけ home-manager の `dconf.settings` に移す。`setThemeDconf.service` が不要になり、3 段構えが 2 段になります
4. GTK / Qt / カーソルを `gtk.*` / `qt.*` と `home.file` に移し、対応する mutable 指定を外す
5. `theme.switch.sh` の呼び出しを `wallpaper.sh` の直接呼び出しに置き換える（案 1）

3 まで進めた時点で、初回 rebuild で dconf が失敗する問題は消えるはずです。home-manager の dconf モジュールは D-Bus セッションが無い場合の面倒を自前で見ますが、activation 時の挙動は実機で確認してください（`journalctl --user` と `dconf dump /org/gnome/desktop/interface`）。ここは未検証です。

#### 効果と費用

得られるものは 2 つです。

- 3 段構えの適用が減り、初回 rebuild の失敗が消える
- テーマ設定が Nix の世界に入るので、利用者が普通の home-manager オプションで上書きできる

失うもの・費用は次のとおりです。

- 上流追従コストが上がります。`theme.switch.sh` が変わるたびに Nix 側の再現も追う必要があります。この危険は仮定の話ではなく、`dconf.set.sh` から `color/dconf.sh` への改名に追従できていない B-8 が実例です。HyDE のスクリプトを呼ぶだけなら改名は追従不要でした。
- A-3 の解決にはなりません。減らせるのは上の表の十数件で、mutable ファイル 115 件の大半は wallbash 由来のため残ります。
- 実機での検証が必須です。GTK4・Qt・カーソルは壊れても気づきにくい割に、壊れたときの体感は悪い部類です。

結論として、設計としては正しい方向ですが、費用に対する効果が限定的です。HyDE のスクリプトをそのまま動かすという現在の方針を捨てて hydenix がテーマ適用を自前で持つ、という方針転換を伴うので、着手するなら issue に判断の理由を残してからにすべきです。一方、段階 1（B-8）と段階 3（dconf のみ）は方針転換を伴わず単独で価値があるため、そこだけ先に進めるのは十分に現実的です。

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

> 案 1 と案 2 を分けて出す必要はありません（案 2 は案 1 を含むため）。

---

## D. dotnix 側で持てばよいもの

hydenix に無くても、利用側（`santamn/dotnix`）で解決できるものです。hydenix 側では扱いません。

| 項目 | 対応 |
|---|---|
| `nh` によるガベージコレクト | dotnix の `modules/nixos/nix.nix` で持つ |
| nixos-anywhere / disko 対応 | dotnix 側で導入する |
| 多ホスト構成 | dotnix の `mkHost` / `hosts/` で対応済み。hydenix と両立する |
