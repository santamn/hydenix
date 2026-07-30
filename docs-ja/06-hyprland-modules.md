# 06. Hyprland モジュールの設計パターン

対象ディレクトリ: [`modules/hm/hyprland/`](../modules/hm/hyprland/)

## ファイル構成

```
hyprland/
├── default.nix      ← 入口。imports と hyprland.conf / userprefs.conf の配置
├── options.nix      ← オプションの定義（ここだけ読めば何ができるか分かる）
├── assertions.nix   ← 危険な設定の検証と警告
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
> オプション名も使い方も本家と同じなので、利用者側の設定はそのまま動きます。変わったのはどこに実装があるかだけです。

## パターン A: 追記 or 置き換え型（`mkHyprConfig`）

### 生成の仕組み

`default.nix` の `imports` で、名前を渡してモジュールを作ります。

```nix
mkHyprConfig = import ./utils/mkHyprConfig.nix {inherit lib pkgs config;};

imports = [
  (mkHyprConfig {name = "hypridle";})
  (mkHyprConfig {name = "keybindings";})
  (mkHyprConfig {name = "monitors";})
  (mkHyprConfig {name = "nvidia";})
  # (mkHyprConfig {name = "pyprland"; extension = "toml";})   ← 無効化されている
  (mkHyprConfig {name = "windowrules";})
  (mkHyprConfig {name = "hyprsunset";})                       ← フォークで追加
];
```

`mkHyprConfig {name = "keybindings";}` を呼ぶと、次のモジュールが返ります。

- **オプション:** `hydenix.hm.hyprland.keybindings.{enable, extraConfig, overrideConfig}`
- **設定:** `~/.config/hypr/keybindings.conf` の配置

### 中身

```nix
config = lib.mkIf (hyprCfg.enable && cfg.enable) {
  home.file.".config/hypr/${name}.${extension}" = {
    text =
      if cfg.overrideConfig != null
      then cfg.overrideConfig                      # 【置き換え】HyDE の設定を一切使わない
      else ''
        ${lib.readFile "${pkgs.hyde}/Configs/.config/hypr/${name}.${extension}"}
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

```nix
# 推奨: 既定の挙動を保ったまま足す
hydenix.hm.hyprland.keybindings.extraConfig = ''
  bind = SUPER, B, exec, firefox
  bind = SUPER SHIFT, S, exec, grim -g "$(slurp)"
'';

# 非推奨: HyDE の機能をほぼ全部失う
hydenix.hm.hyprland.keybindings.overrideConfig = ''
  bind = SUPER, Return, exec, kitty
'';
```

`override` 系を使うと `assertions.nix` が rebuild のたびに警告を出します。

```
hydenix.hm.hyprland: The following configs are overriding Hyde defaults.
Note this may break hydenix, hope you know what you're doing!
(set suppressWarnings = true to hide this warning): keybindings.overrideConfig
```

自覚した上で使うなら `suppressWarnings = true;` で黙らせられます。

> [!NOTE]
> `assertions.nix` は `hypridle` / `keybindings` / `windowrules` / `nvidia` / `monitors` / `overrideMain` しか見ていません。
> フォークで追加された **`hyprsunset`** は検証対象から漏れています。

### monitors について

本家では `monitors.nix` だけが `extraConfig` なし・`mutable = true` という特別扱いでした。フォークでは `mkHyprConfig` に統合されたため、`monitors` にも `extraConfig` が使えます。また `mutable = true` は全モジュール共通になりました。

内容を Nix で固定したい場合は従来通り `overrideConfig` を使います。

```nix
hydenix.hm.hyprland.monitors.overrideConfig = ''
  monitor = DP-1, 2560x1440@144, 0x0, 1
  monitor = HDMI-A-1, 1920x1080@60, 2560x0, 1
'';
```

### pyprland が使えない件

`default.nix` の imports でコメントアウトされており、オプションも存在しません。本家 issue #188（`hyde-shell pypr console` が動かない）が未解決のためです。

そのため scratchpad などの pyprland 機能は使えません。`hydenix.hm.hyprland.pyprland.extraConfig = "...";` と書くと、本家と違って**オプション未定義エラーで止まります**。

## パターン B: プリセット選択型

`animations` / `shaders` / `workflows` が該当します。「複数の候補ファイルを全部置いておき、そのうち 1 つを有効にする」構造です。

```nix
config = lib.mkIf (cfg.enable && cfg.animations.enable) {
  home.file = lib.mkMerge [
    # (1) 現在有効なプリセット → animations.conf
    {".config/hypr/animations.conf" = ...;}

    # (2) 全プリセット → animations/<名前>.conf
    (lib.listToAttrs (map (preset: {name = "..."; value = ...;}) animationPresets))
  ];
};
```

(2) で全プリセットを配置しているのは、**実行中に HyDE の機能で切り替えられるようにするため**です。

### overrides の使い方

```nix
hydenix.hm.hyprland.animations = {
  preset = "my-custom";           # ← overrides に無い名前でもよい
  overrides = {
    "my-custom" = ''
      animation = windows, 1, 3, default
      animation = fade, 1, 3, default
    '';
    "standard" = ''               # 既存プリセットの上書きもできる
      animation = global, 0, 0, default
    '';
  };
};
```

判定は「`overrides` にそのキーがあるか」だけで行われます。

```nix
if cfg.animations.overrides ? ${cfg.animations.preset} then <overrides の中身> else <HyDE のファイル>
```

> [!WARNING]
> `preset` に「overrides にも HyDE にも無い名前」を書くと、`${pkgs.hyde}/Configs/.config/hypr/animations/<名前>.conf` が存在せず、**ビルドが失敗します**。テーマ名と違い、こちらは黙って無視されません。

`workflows.nix` だけは追加処理があり、標準プリセットに無い名前の `overrides` を新規ワークフローとしても配置します。

```nix
(lib.mapAttrs' (name: content: {...})
  (lib.filterAttrs (name: _: !(lib.elem name workflowPresets)) cfg.workflows.overrides))
```

`shaders.nix` の `overrides` はキーに**拡張子まで含めて**書く点が他と異なります（例: `"my-filter.frag"`）。

## メイン設定の扱い

`default.nix` が 2 つのファイルを配置します。

```nix
".config/hypr/hyprland.conf"   # HyDE 本体（overrideMain で丸ごと置き換え可能）
".config/hypr/userprefs.conf"  # extraConfig の内容が入る。hyprland.conf の最後に読み込まれる
```

**通常のカスタマイズは `extraConfig` に書きます。**

```nix
hydenix.hm.hyprland.extraConfig = ''
  input {
    kb_options = ctrl:swapcaps
    touchpad {
      natural_scroll = true
      clickfinger_behavior = true
    }
  }
  exec-once = fcitx5
'';
```

`overrideMain` は HyDE の機能をほぼ全部失うため、HyDE のレイアウトを土台にしたくないという明確な意図がある場合のみ使います。

## systemd 連携（フォークで追加）

`hyprland.conf` の末尾に、次の 1 行が自動で足されます。

```
exec-once = <dbus>/bin/dbus-update-activation-environment --systemd DISPLAY HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE && systemctl --user stop hyprland-session.target && systemctl --user start hyprland-session.target
```

これにより、systemd ユーザサービス側から `WAYLAND_DISPLAY` などが見えるようになります。テーマ適用サービス（`setTheme.service`）が正しく動くための前提です。

```nix
hydenix.hm.hyprland.systemd = {
  enable = true;                 # hyprland-session.target を作る
  variables = [...];             # 流し込む環境変数（既定で 5 つ）
  extraCommands = [...];         # D-Bus 起動後に走らせるコマンド
  enableXdgAutostart = false;    # XDG autostart を有効にするか
};
```

## activation script が空ファイルを作る理由

```nix
home.activation.createHyprConfigs = lib.hm.dag.entryAfter ["mutableGeneration"] ''
  mkdir -p "$HOME/.config/hypr/themes"
  touch "$HOME/.config/hypr/themes/colors.conf"
  ...
'';
```

これらは**テーマ適用スクリプトが後で書き込む先**のファイルです。Hyprland は設定ファイル内の `source = ...` で存在しないファイルを指すとエラーを出すため、初回起動時のエラーを防ぐために空ファイルを先に用意しています。

> [!NOTE]
> 依存先に指定されている `"mutableGeneration"` は、`mutable.nix` が実際に定義している名前 `"mutableFileGeneration"` と食い違っています。
> 詳細は [08-improvements.md](./08-improvements.md) を参照。

## 設定を変更したときの反映

Hyprland は設定ファイルの変更を自動で再読み込みします。ただし hydenix 経由で変更した場合は、まず rebuild が必要です。

```bash
sudo nixos-rebuild switch --flake .#<ホスト名>
# → ~/.config/hypr/*.conf が更新される
# → Hyprland が自動で再読み込みする（されない場合は hyprctl reload）
```

> [!TIP]
> `mkHyprConfig` の生成物は `mutable = true` なので、**手動で編集した内容は次の rebuild まで残ります**。試行錯誤するときは直接編集 → `hyprctl reload` が速く、決まったら `extraConfig` に書き戻す、という進め方ができます。
