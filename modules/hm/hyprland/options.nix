# =============================================================================
# Hyprland モジュールのオプション定義（config は各ファイルが持つ）
#
# 「何が設定できるか」を 1 ファイルで見渡せるのが利点。
# 逆に「その設定がどう反映されるか」は個別ファイルを見る必要がある。
#
# ここに無い hypridle / hyprlock / hyprsunset のオプションは
# utils/mkHyprConfig.nix が動的に生成している。
# =============================================================================
{
  config,
  lib,
  ...
}: let
  cfg = config.hydenix.hm.hyprland;
in {
  options.hydenix.hm.hyprland = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable hyprland module";
    };
    # 通常のカスタマイズはここ。Lua で書き、ユーザ層の ~/.config/hypr/hyprland.lua に入る。
    # hyde.lua が HyDE のモジュールを読んだ後に読まれるので、HyDE の既定値を上書きできる
    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra config appended to hyprland.lua";
    };
    # hyprland.lua を丸ごと差し替える。systemd 連携の Lua も入らなくなるので非推奨
    overrideMain = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = "Complete override of hyprland.lua";
    };
    # override 使用時の警告を黙らせる（警告は default.nix と mkHyprConfig.nix が出す）
    suppressWarnings = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Suppress warnings about configuration overrides";
    };

    # systemd 連携（フォークで追加された機能）。
    # Hyprland 起動時に環境変数を systemd / D-Bus のユーザ環境へ流し込み、
    # hyprland-session.target を起動する
    systemd = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = ''
          Whether to enable {file}`hyprland-session.target` on
          hyprland startup. This links to `graphical-session.target`.
          Some important environment variables will be imported to systemd
          and D-Bus user environment before reaching the target, including
          - `DISPLAY`
          - `HYPRLAND_INSTANCE_SIGNATURE`
          - `WAYLAND_DISPLAY`
          - `XDG_CURRENT_DESKTOP`
          - `XDG_SESSION_TYPE`
        '';
      };

      variables = lib.mkOption {
        type = with lib.types; listOf str;
        default = [
          "DISPLAY"
          "HYPRLAND_CONFIG"
          "HYPRLAND_INSTANCE_SIGNATURE"
          "WAYLAND_DISPLAY"
          "XDG_CURRENT_DESKTOP"
          "XDG_SESSION_TYPE"
        ];
        example = ["--all"];
        description = ''
          Environment variables to be imported in the systemd & D-Bus user
          environment.
        '';
      };

      extraCommands = lib.mkOption {
        type = with lib.types; listOf str;
        default = [
          "systemctl --user stop hyprland-session.target"
          "systemctl --user start hyprland-session.target"
        ];
        description = "Extra commands to be run after D-Bus activation.";
      };

      enableXdgAutostart = lib.mkEnableOption ''
        autostart of applications using
        {manpage}`systemd-xdg-autostart-generator(8)`'';
    };

    # Animation configurations
    # プリセット選択型。overrides に無く HyDE にも無い preset 名は assertion で評価が止まる
    animations = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Enable animation configurations";
      };
      preset = lib.mkOption {
        type = lib.types.str;
        default = "standard";
        description = "Animation preset to use";
        example = lib.literalExpression ''
          "standard" # a name in overrides, or one HyDE ships: "00-disable", "01-default", "classic", "diablo-1", "diablo-2", "end4", "fast", "gnome", "ja", "limefrenzy", "macos", "me-1", "me-2", "minimal-2", "moving", "optimized", "standard", "vertical"
        '';
      };
      overrides = lib.mkOption {
        type = lib.types.attrsOf lib.types.lines;
        default = {};
        description = "Override or add animation presets, written in Lua; names must not contain dots";
        example = lib.literalExpression ''
          {
            "my-animations" = '''
              if not hl then
                return { name = "My animations" }
              end
              hl.animation({ leaf = "windows", enabled = true, speed = 5, bezier = "default" })
            ''';
          }
        '';
      };
    };

    # Shader configurations
    # overrides のキーは拡張子まで含めて書く（例: "my-filter.frag"）
    shaders = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Enable shader configurations";
      };
      active = lib.mkOption {
        type = lib.types.str;
        default = "disable";
        description = "Active shader preset";
        example = lib.literalExpression ''
          "disable" # a name in overrides without .frag, or one HyDE ships: "blue-light-filter", "color-vision", "custom", "grayscale", "invert-colors", "oled-saver", "paper", "vibrance", "wallbash"
        '';
      };
      overrides = lib.mkOption {
        type = lib.types.attrsOf lib.types.lines;
        default = {};
        description = "Override or add custom shaders";
        example = lib.literalExpression ''
          {
            "my-filter.frag" = '''
              precision mediump float;
              // Custom shader code
            ''';
          }
        '';
      };
    };

    # Workflow configurations
    # 標準プリセットに無い名前を overrides に書くと、新規ワークフローとして追加される
    workflows = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Enable workflow configurations";
      };
      active = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "Active workflow preset";
        example = lib.literalExpression ''
          "default" # a name in overrides, or one HyDE ships: "editing", "gaming", "powersaver", "snappy"
        '';
      };
      overrides = lib.mkOption {
        type = lib.types.attrsOf lib.types.lines;
        default = {};
        description = "Override or add workflows, written in Lua; names must not contain dots";
        example = lib.literalExpression ''
          {
            "my-workflow" = '''
              if not hl then
                return { name = "My workflow" }
              end
              hl.config({ general = { gaps_out = 0 } })
            ''';
          }
        '';
      };
    };
  };
}
