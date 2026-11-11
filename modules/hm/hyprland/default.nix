# =============================================================================
# Hyprland 設定モジュールの入口
#
# ■ HyDE v26.08.21 以降の読み込み順
#   Hyprland は ~/.local/share/hypr/hyde.lua から起動し、HyDE のモジュール、
#   ユーザ層の ~/.config/hypr/hyprland.lua、選択中のワークフローの順に読む。
#   以前の .conf（hyprland.conf / userprefs.conf など）はもう読まれない。
#
# ■ ファイル構成
#   default.nix   … このファイル。imports と hyprland.lua / hyprlock/ の配置、systemd target
#   options.nix   … オプション定義（何が設定できるかはここだけ読めば分かる）
#   presets.nix   … HyDE が同梱するプリセット名の一覧（存在チェックに使う）
#   animations / shaders / workflows … プリセット選択型（activation で hyde-shell が切り替える）
#   utils/mkHyprConfig.nix … 「追記 or 置き換え」型モジュールを名前から生成する関数
#
# ■ 本家との違い
#   本家では hypridle.nix / keybindings.nix / ... が個別ファイルだった。
#   このフォークでは同じ構造のものを mkHyprConfig にまとめ、Lua 化に伴って
#   keybindings / monitors / nvidia / windowrules は廃止した（extraConfig の Lua に書く）。
#
# 詳細は docs-ja/06-hyprland-modules.md を参照。
# =============================================================================
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.hyprland;
  # 「追記 or 置き換え」型モジュールを名前から生成するファクトリ
  mkHyprConfig = import ./utils/mkHyprConfig.nix {inherit lib pkgs config;};

  # Hyprland 起動時に、systemd と D-Bus のユーザ環境へ環境変数を流し込む Lua を組み立てる。
  # これが無いと systemd ユーザサービス（setTheme.service など）から
  # WAYLAND_DISPLAY や HYPRLAND_CONFIG が見えない。
  # Hyprland 0.57 は自分で hyprland-session.target を起動してしまうので、
  # HYPRLAND_NO_SD_TARGET で止め、環境変数を流し込んだ後にこちらで起動し直す
  variables = builtins.concatStringsSep " " cfg.systemd.variables;
  extraCommands = builtins.concatStringsSep " " (map (f: "&& ${f}") cfg.systemd.extraCommands);
  # Runs once when Hyprland starts, like exec-once; a reload does not run it again
  systemdActivation = ''
    -- Hyprland 0.57 starts hyprland-session.target itself, before the handler below imports HYPRLAND_CONFIG.
    -- Leave the target to the handler, so setTheme.service and the other units it pulls in always see the variable.
    hl.env("HYPRLAND_NO_SD_TARGET", "1")
    hl.on("hyprland.start", function()
      hl.exec_cmd(${builtins.toJSON "${pkgs.dbus}/bin/dbus-update-activation-environment --systemd ${variables} ${extraCommands}"})
    end)
  '';

  # 生成した hyprland.lua を luac -p で構文チェックする。
  # 構文エラーがあるとログイン時にファイルごと読み飛ばされるので、ビルドで止める
  # Writes hyprland.lua and fails the build on a Lua syntax error, which Hyprland would report only after login
  luaFile = text:
    pkgs.writeTextFile {
      name = "hyprland.lua";
      inherit text;
      checkPhase = ''
        ${pkgs.lua5_5}/bin/luac -p "$target" || {
          cat -n "$target" >&2
          echo "hydenix.hm.hyprland: hyprland.lua above is not valid Lua; since HyDE v26.08.21, extraConfig and overrideMain take Lua (see HyDE's MIGRATION-LUA.md)" >&2
          exit 1
        }
      '';
    };
in {
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

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (cfg.overrideMain != null && !cfg.suppressWarnings) "hydenix.hm.hyprland.overrideMain is overriding hydenix's hyprland.lua. Note this may break hydenix, hope you know what you're doing! (set hydenix.hm.hyprland.suppressWarnings = true to hide this warning)";

    # Always include packages and base setup
    home.packages = [
      pkgs.hyprutils
      pkgs.hyprpicker
      pkgs.hyprcursor
      # <name>.conf を配置するだけでは本体が入らないため、
      # モジュールを有効にしたときだけパッケージも一緒に入れる
      (lib.mkIf cfg.hyprlock.enable pkgs.hyprlock)
      (lib.mkIf cfg.hyprsunset.enable pkgs.hyprsunset)
    ];

    # wallbash が後から書き込む colors.conf を、空で先に用意しておく。
    # hyprlock は存在しないファイルを source するとエラーを出すため、初回起動時のエラーを防ぐのが目的。
    #
    # 依存先は mutable.nix が定義する "mutableFileGeneration"。
    # run は Home Manager の関数で、dry-run のときはコマンドを実行せずに表示だけする
    # hyprlock sources the colors wallbash writes here
    home.activation.createHyprConfigs = lib.hm.dag.entryAfter ["mutableFileGeneration"] ''
      run mkdir -p "$HOME/.config/hypr/themes"
      run touch "$HOME/.config/hypr/themes/colors.conf"
      run chmod 644 "$HOME/.config/hypr/themes/colors.conf"
    '';

    home.file = {
      ".local/share/hypr/" = {
        source = "${pkgs.hyde}/Configs/.local/share/hypr/";
        recursive = true;
        force = true;
      };

      # ユーザ層の hyprland.lua。overrideMain を指定すると中身を丸ごと差し替える（非推奨）。
      # 差し替えてもユーザ層だけなので、HyDE のキーバインドやウィンドウルールは先に読み込まれる。
      # 通常は systemd 連携の Lua と extraConfig を並べたファイルを生成する
      # The user layer that hyde.lua, HyDE's entry point, loads after its own config
      ".config/hypr/hyprland.lua" =
        if cfg.overrideMain != null
        then {
          source = luaFile cfg.overrideMain;
          force = true;
        }
        else {
          source = luaFile ''
            -- Hyprland starts from this file only when started without -c or HYPRLAND_CONFIG.
            -- hyde.lua then loads this file again as its user layer, so stop here instead of running it twice.
            if not hyde then
              dofile((os.getenv("XDG_DATA_HOME") or os.getenv("HOME") .. "/.local/share") .. "/hypr/hyde.lua")
              return
            end

            ${lib.optionalString cfg.systemd.enable systemdActivation}
            ${cfg.extraConfig}
          '';
          force = true;
        };

      # hyprlock のレイアウト一式。wallbash が theme.conf を書き込むので mutable にしている
      ".config/hypr/hyprlock" = lib.mkIf cfg.hyprlock.enable {
        source = "${pkgs.hyde}/Configs/.config/hypr/hyprlock";
        recursive = true;
        force = true;
        mutable = true;
      };
    };

    # Hyprland セッション用の systemd target。
    # graphical-session.target に紐づくので、テーマ適用サービス等がここを起点に動く
    systemd.user.targets.hyprland-session = lib.mkIf cfg.systemd.enable {
      Unit = {
        Description = "Hyprland compositor session";
        Documentation = ["man:systemd.special(7)"];
        BindsTo = ["graphical-session.target"];
        Wants =
          [
            "graphical-session-pre.target"
          ]
          ++ lib.optional cfg.systemd.enableXdgAutostart "xdg-desktop-autostart.target";
        After = ["graphical-session-pre.target"];
        Before = lib.mkIf cfg.systemd.enableXdgAutostart ["xdg-desktop-autostart.target"];
      };
    };
  };
}
