# 06. Hyprland モジュールの設計パターン

対象ディレクトリ: [`modules/hm/hyprland/`](../modules/hm/hyprland/)

## ファイル構成

```text
hyprland/
├── default.nix      ← 入口。imports と hyprland.lua / hyprlock/ の配置、systemd target
├── options.nix      ← オプションの定義（ここだけ読めば何ができるか分かる）
├── presets.nix      ← HyDE が同梱するプリセット名の一覧（名前の検査に使う）
│
├── animations.nix   ┐
├── shaders.nix      │ プリセット選択型
├── workflows.nix    ┘
│
└── utils/
    └── mkHyprConfig.nix  ← 「追記 or 置き換え」型モジュールを動的生成する関数
```

**設計の要点:** `options.nix` に定義を集め、`config`（適用処理）は各ファイルが持ちます。何が設定できるかは1ファイルに集約されており、その設定がどう反映されるかについては個別ファイルを見る必要があります。

> [!IMPORTANT]
> フォークでの最大の変更点がここです。本家には `hypridle.nix` / `keybindings.nix` / `windowrules.nix` / `nvidia.nix` / `monitors.nix` / `pyprland.nix` という個別ファイルがありましたが、すべて同じ構造だったため、`mkHyprConfig.nix` という関数に一本化されました。
>
> さらにフォークは HyDE v26.08.21 に追従しており、Hyprland の設定は hyprlang の `.conf` ではなく Lua で書きます。`mkHyprConfig` で作るのは、Lua 化の後も hyprlang のまま残った `hypridle` / `hyprlock` / `hyprsunset` の 3 つだけです。`keybindings` / `monitors` / `nvidia` / `windowrules` のオプションは無く、キーバインド・ウィンドウルール・モニタは `extraConfig` に Lua で書きます（[メイン設定の扱い](#メイン設定の扱い)）。NVIDIA 用の環境変数は、NVIDIA ドライバが読み込まれているときだけ HyDE の `lua/env.lua` が設定します。
>
> そのため、本家向けに書いた `hydenix.hm.hyprland.*` の設定はそのままでは動きません。`extraConfig` は Lua で書き直す必要があり、`keybindings` などは未定義のオプションになります。

## パターン A: 追記 or 置き換え型（`mkHyprConfig`）

### 生成の仕組み

`default.nix` の `imports` で、名前を渡してモジュールを作ります。

```nix
mkHyprConfig = import ./utils/mkHyprConfig.nix {inherit lib pkgs config;};

imports = [
  ./animations.nix
  ./options.nix
  ./shaders.nix
  ./workflows.nix
  # mkHyprConfig で生成されるモジュール群。
  # それぞれ hydenix.hm.hyprland.<name>.{enable,extraConfig,overrideConfig} を提供し、
  # ~/.config/hypr/<name>.conf を配置する（この 3 つは Lua 化後も hyprlang のまま）
  (mkHyprConfig {name = "hypridle";})
  (mkHyprConfig {name = "hyprlock";})
  (mkHyprConfig {name = "hyprsunset";}) # フォーク独自追加（ブルーライト低減）
];
```

`mkHyprConfig` が用意するのは設定ファイルの配置だけで、コマンド本体は入りません。`hyprlock` と `hyprsunset` の本体は、`default.nix` の `home.packages` に `lib.mkIf cfg.hyprlock.enable pkgs.hyprlock` / `lib.mkIf cfg.hyprsunset.enable pkgs.hyprsunset` を足して、モジュールを有効にしたときだけ入れています。`hypridle` の本体は `modules/system/system.nix` がシステム全体に入れています。

`mkHyprConfig {name = "hypridle";}` を呼ぶと、次のモジュールが返ります。

- **オプション:** `hydenix.hm.hyprland.hypridle.{enable, extraConfig, overrideConfig}`
- **設定:** `~/.config/hypr/hypridle.conf` の配置と、`overrideConfig` を使ったときの警告

### 中身

```nix
config = lib.mkIf (hyprCfg.enable && cfg.enable) {
  warnings = lib.optional (cfg.overrideConfig != null && !hyprCfg.suppressWarnings) "hydenix.hm.hyprland.${name}.overrideConfig is overriding Hyde defaults. ...";

  home.file.".config/hypr/${name}.conf" = {
    text =
      if cfg.overrideConfig != null
      then cfg.overrideConfig                      # 【置き換え】HyDE の設定を一切使わない
      else ''
        ${lib.readFile "${pkgs.hyde}/Configs/.config/hypr/${name}.conf"}
        ${cfg.extraConfig}                         # 【追記】HyDE の設定の後ろに足す
      '';
    force = true;
    mutable = true;
  };
};
```

### なぜ `source` ではなく `lib.readFile` なのか

| 書き方 | できること |
|-------|----------|
| `source = "${pkgs.hyde}/..."` | HyDE のファイルへリンクを張るだけ。中身は変えられない |
| `text = "${lib.readFile ...}\n追記"` | 中身を読み込んで**新しいファイルを生成**するので追記できる |

`extraConfig` を提供するには後者でなければ実現できません。

### 使い分け

3 つとも hyprlang のファイルなので、`extraConfig` と `overrideConfig` も hyprlang で書きます。

```nix
# 推奨: 既定の挙動を保ったまま足す
hydenix.hm.hyprland.hypridle.extraConfig = ''
  listener {
    timeout = 1800
    on-timeout = systemctl hibernate
  }
'';

# 非推奨: HyDE の hypridle.conf（減光・ロック・画面オフ・サスペンド）を丸ごと捨てる
hydenix.hm.hyprland.hypridle.overrideConfig = ''
  listener {
    timeout = 300
    on-timeout = loginctl lock-session
  }
'';
```

`overrideConfig` を使うと、そのモジュール自身が rebuild のたびに警告を出します。

```text
hydenix.hm.hyprland.hypridle.overrideConfig is overriding Hyde defaults. Note this may break hydenix, hope you know what you're doing! (set hydenix.hm.hyprland.suppressWarnings = true to hide this warning)
```

自覚した上で使うなら `hydenix.hm.hyprland.suppressWarnings = true;` で警告を非表示にできます。

`overrideConfig` の型は `nullOr nonEmptyStr` です。空文字や空白だけの文字列を書くと、モジュールシステムが型エラーで止め、どのファイルで定義したかを表示します。

### pyprland が使えない件

hydenix は pyprland の設定を配置せず、オプションもありません。HyDE は `~/.config/pypr/config.toml` を同梱していますが、どのモジュールもこれを配置しません。本家 issue #188（`hyde-shell pypr console` が動かない）は未解決のままです。

そのため scratchpad などの pyprland 機能は使えません。`hydenix.hm.hyprland.pyprland.extraConfig = "...";` と書くと、本家と違って**オプション未定義エラーで止まります**。

## パターン B: プリセット選択型

`animations` / `shaders` / `workflows` が該当します。「HyDE が同梱する候補をすべて置いておき、そのうち 1 つを有効にする」構造です。

候補の置き場所は種類によって異なります。アニメーションとワークフローは `~/.local/share/hypr/lua/{animations,workflows}/<名前>.lua` にあり、`default.nix` が `~/.local/share/hypr/` ごと HyDE のファイルへリンクしています。シェーダは `shaders.nix` が `~/.config/hypr/shaders/<名前>.frag` として 1 つずつリンクします。

どれを有効にするかは、rebuild の activation で HyDE のセレクタ（`hyde-shell <セレクタ> --set <名前>`）を実行して決めます。

```nix
home.activation.setAnimationPreset = lib.hm.dag.entryAfter ["mutableFileGeneration"] ''
  run ${pkgs.hyde}/Configs/.local/bin/hyde-shell animations --set ${lib.escapeShellArg cfg.animations.preset}
'';
```

セレクタは選んだプリセットを `~/.local/state/hyde/lua_state/` の状態ファイルに書き、Hyprland はそれを `hyde.lua` から読み込みます。シェーダはこのときにコンパイルされます。`setShader` だけは `setTheme` の後に実行されます。wallbash シェーダが、テーマ切り替えの書き出す色を include するためです。

候補をすべて置いているのは、**実行中に HyDE の機能で切り替えられるようにするため**です。ただし実行中に切り替えた選択は、次の rebuild で activation が Nix 側の指定に戻します。

### overrides の使い方

アニメーションとワークフローの `overrides` は Lua で書きます。先頭の `if not hl then ... end` は、HyDE が同梱するプリセットと同じ書き方です。

```nix
hydenix.hm.hyprland.animations = {
  preset = "my-custom";           # ← overrides のキーも選べる
  overrides = {
    "my-custom" = ''
      if not hl then
        return { name = "My animations" }
      end
      hl.animation({ leaf = "windows", enabled = true, speed = 5, bezier = "default" })
    '';
    # HyDE の同名プリセットを置き換える
    "standard" = ''
      if not hl then
        return { name = "Standard" }
      end
      hl.animation({ leaf = "global", enabled = false })
    '';
  };
};
```

`overrides` に書いたものは、アニメーションなら `~/.config/hypr/lua/animations/<名前>.lua`、ワークフローなら `~/.config/hypr/workflows/<名前>.lua` に置かれます。HyDE のセレクタは `~/.config/hypr` 側を `~/.local/share/hypr` 側より先に探し、`pkgs/hyde/default.nix` のパッチによって、同名のプリセットがあれば先に見つけたほうを使います。そのため HyDE と同じ名前なら HyDE のプリセットを置き換え、新しい名前なら新しいプリセットとして選べるようになります。

`overrides` のキーには `.` と `/` を使えません。HyDE はプリセットを Lua の `require` で読み込み、`require` はドットをディレクトリの区切りとして扱うためです。違反すると assertion で評価が止まります。

評価の時点で、選んだ名前が候補の一覧にあるかを assertion で調べます。

```nix
presets = map lib.toLower ((import ./presets.nix).animations ++ lib.attrNames cfg.animations.overrides);
...
assertion = lib.elem (lib.toLower cfg.animations.preset) presets;
```

候補は `presets.nix` に書かれた HyDE 同梱の名前と、`overrides` のキーを合わせたものです。大文字小文字は区別しません（HyDE のセレクタと同じ）。`presets.nix` は手で書いた一覧ですが、flake の `hyprland-config` チェックが `pkgs.hyde` の実ファイルの一覧と比べるので、HyDE の更新でプリセットが増減するとチェックが失敗します。

> [!WARNING]
> `preset` に「overrides にも HyDE にも無い名前」を書くと、**assertion で評価が止まり**、選べる名前の一覧がエラーメッセージに出ます。警告も出さずに無視されるテーマ名とは扱いが違います。

`workflows.active` の既定値 `"default"` は `01-default.lua` の表示名です。HyDE のセレクタはファイル名と表示名のどちらでもプリセットを引けるので、`workflows.nix` は候補に `"default"` を足しています。

`shaders.nix` の `overrides` はキーに**拡張子まで含めて**書く点が他と異なります（例: `"my-filter.frag"`）。HyDE と同名のキー（`"wallbash.frag"` など）は `lib.mkForce` で HyDE のファイルを置き換えます。

## メイン設定の扱い

Hyprland は `~/.local/share/hypr/hyde.lua` から起動します。`hyde.nix` がセッション変数 `HYPRLAND_CONFIG` でこのファイルを指しています。`hyde.lua` は HyDE の Lua モジュール（変数、既定値、ウィンドウルール、キーバインド、起動処理など）を読んだ後、ユーザ層の `~/.config/hypr/hyprland.lua`、選択中のワークフローの順に読み込みます。

`default.nix` はこのうち次の 2 つを配置します。

```nix
".local/share/hypr/"          # HyDE の hyde.lua と lua/ 一式（HyDE のファイルへのリンク）
".config/hypr/hyprland.lua"   # ユーザ層。systemd 連携の Lua と extraConfig が入る（overrideMain で丸ごと置き換え可能）
```

生成される `hyprland.lua` の先頭には、次のブロックが入ります。`HYPRLAND_CONFIG` を指定せずに起動した Hyprland は最初にこのファイルを読むので、そのときは `hyde.lua` を読み込んで終わります。`hyde.lua` がこのファイルをユーザ層としてもう一度読むため、ここで止めないと二重に実行されます。

```lua
-- Hyprland starts from this file only when started without -c or HYPRLAND_CONFIG.
-- hyde.lua then loads this file again as its user layer, so stop here instead of running it twice.
if not hyde then
  dofile((os.getenv("XDG_DATA_HOME") or os.getenv("HOME") .. "/.local/share") .. "/hypr/hyde.lua")
  return
end
```

**通常のカスタマイズは `extraConfig` に Lua で書きます。** ユーザ層は HyDE のモジュールより後に読まれるので、HyDE の既定値を上書きできます。キーバインド（`hl.bind`）、ウィンドウルール（`hl.window_rule`）、モニタ（`hl.monitor`）もここに書きます。書き方は HyDE の `MIGRATION-LUA.md` にあります。

```nix
hydenix.hm.hyprland.extraConfig = ''
  hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = 1 })
  hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60", position = "2560x0", scale = 1 })
  hl.config({
    input = {
      kb_options = "ctrl:swapcaps",
      touchpad = {
        natural_scroll = true,
        clickfinger_behavior = true,
      },
    },
  })
  hl.on("hyprland.start", function()
    hl.exec_cmd("fcitx5")
  end)
'';
```

`hyprland.lua` はビルド時に `luac -p` で構文を確かめ、構文エラーがあればビルドを止めます。構文エラーのあるファイルはログイン時に丸ごと読み飛ばされ、ログインするまで気づけないためです。

`overrideMain` は `hyprland.lua` を丸ごと差し替えます。差し替わるのはユーザ層だけなので、HyDE のキーバインドやウィンドウルールはその前に読み込まれます。ただし上のブロックも systemd 連携の Lua も入らなくなります。使うと `default.nix` が rebuild のたびに警告を出すので、`extraConfig` で足りない明確な理由がある場合のみ使います。

## systemd 連携（フォークで追加）

`hydenix.hm.hyprland.systemd.enable` が有効なとき、`hyprland.lua` の `extraConfig` の前に次の Lua が自動で足されます（`<dbus>` は dbus パッケージのストアパス）。

```lua
-- Hyprland 0.57 starts hyprland-session.target itself, before the handler below imports HYPRLAND_CONFIG.
-- Leave the target to the handler, so setTheme.service and the other units it pulls in always see the variable.
hl.env("HYPRLAND_NO_SD_TARGET", "1")
hl.on("hyprland.start", function()
  hl.exec_cmd("<dbus>/bin/dbus-update-activation-environment --systemd DISPLAY HYPRLAND_CONFIG HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE && systemctl --user stop hyprland-session.target && systemctl --user start hyprland-session.target")
end)
```

`hyprland.start` のハンドラは、hyprlang の `exec-once` と同じく Hyprland の起動時に 1 回だけ実行され、reload では実行されません。これにより、systemd ユーザサービス側から `WAYLAND_DISPLAY` や `HYPRLAND_CONFIG` などが見えるようになります。テーマ適用サービス（`setTheme.service`）が正しく動くための前提です。

`HYPRLAND_NO_SD_TARGET` を設定しているのは、Hyprland 0.57 が起動時に自分で `hyprland-session.target` を起動するためです。そのままだと、ハンドラによる `HYPRLAND_CONFIG` の流し込みより先に target が起動します。すると、target に引き込まれた `setTheme.service` は、この変数なしで動くことがあります。`HYPRLAND_NO_SD_TARGET` で Hyprland 側の起動を止め、target の起動をハンドラに任せています。

```nix
hydenix.hm.hyprland.systemd = {
  enable = true;                 # hyprland-session.target を作り、上の Lua を hyprland.lua に入れる
  variables = [...];             # 流し込む環境変数（既定で 6 つ）
  extraCommands = [...];         # D-Bus 起動後に走らせるコマンド
  enableXdgAutostart = false;    # XDG autostart を有効にするか
};
```

## activation script が空ファイルを作る理由

```nix
home.activation.createHyprConfigs = lib.hm.dag.entryAfter ["mutableFileGeneration"] ''
  run mkdir -p "$HOME/.config/hypr/themes"
  run touch "$HOME/.config/hypr/themes/colors.conf"
  run chmod 644 "$HOME/.config/hypr/themes/colors.conf"
'';
```

`colors.conf` は**wallbash が後で書き込む先**のファイルです。hyprlock は HyDE の `~/.local/share/hypr/hyprlock.conf` 経由でこのファイルを `source` しており、存在しないファイルを `source` するとエラーを出します。初回起動時のエラーを防ぐために、空ファイルを先に用意しています。

> [!NOTE]
> 依存先の `"mutableFileGeneration"` は `mutable.nix` が定義しているエントリ名です。`run` は Home Manager のシェル関数で、dry-run のときはコマンドを実行せずに表示だけします。

## 設定を変更したときの反映

Hyprland は設定ファイルの変更を自動で再読み込みします。ただし hydenix 経由で変更した場合は、まず rebuild が必要です。

```bash
sudo nixos-rebuild switch --flake .#<ホスト名>
# → ~/.config/hypr/hyprland.lua などが更新され、activation がプリセットを選び直す
# → Hyprland が自動で再読み込みする（されない場合は hyprctl reload）
```

> [!TIP]
> `hyprland.lua` は Nix ストアのファイルへのリンクなので、直接は編集できません。一方 `mkHyprConfig` の生成物（`hypridle.conf` / `hyprlock.conf` / `hyprsunset.conf`）は `mutable = true` なので、**手動で編集した内容は次の rebuild まで残ります**。試行錯誤するときは直接編集して確かめ、決まったら `extraConfig` に書き戻す、という進め方ができます。
