# =============================================================================
# Hyprland 設定モジュールの入口
#
# ■ ファイル構成
#   default.nix   … このファイル。imports と hyprland.conf / userprefs.conf の配置
#   options.nix   … オプション定義（何が設定できるかはここだけ読めば分かる）
#   assertions.nix… override 系を使ったときの検証と警告
#   animations / shaders / workflows … プリセット選択型（候補を全部置いて 1 つ選ぶ）
#   utils/mkHyprConfig.nix … 「追記 or 置き換え」型モジュールを動的生成する関数
#
# ■ 本家との違い
#   本家では hypridle.nix / keybindings.nix / ... が個別ファイルだったが、
#   このフォークでは同じ構造だったため mkHyprConfig で 1 本化されている。
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

  # Hyprland 起動時に、systemd と D-Bus のユーザ環境へ環境変数を流し込む行を組み立てる。
  # これが無いと systemd ユーザサービス側から WAYLAND_DISPLAY 等が見えない
  variables = builtins.concatStringsSep " " cfg.systemd.variables;
  extraCommands = builtins.concatStringsSep " " (map (f: "&& ${f}") cfg.systemd.extraCommands);
  systemdActivation = ''
    exec-once = ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd ${variables} ${extraCommands}
  '';
in {
  imports = [
    ./animations.nix
    ./assertions.nix
    ./options.nix
    ./shaders.nix
    ./workflows.nix
    # mkHyprConfig で生成されるモジュール群。
    # それぞれ hydenix.hm.hyprland.<name>.{enable,extraConfig,overrideConfig} を提供し、
    # ~/.config/hypr/<name>.conf を配置する
    (mkHyprConfig {name = "hypridle";})
    (mkHyprConfig {name = "keybindings";})
    (mkHyprConfig {name = "monitors";})
    (mkHyprConfig {name = "nvidia";})
    # pyprland は無効化されている（本家 issue #188: hyde-shell pypr console が動かない）。
    # そのため scratchpad などの pyprland 機能は使えない
    # (mkHyprConfig {name = "pyprland"; extension = "toml";})
    (mkHyprConfig {name = "windowrules";})
    (mkHyprConfig {name = "hyprsunset";}) # フォーク独自追加（ブルーライト低減）
  ];

  config = lib.mkIf cfg.enable {
    # Always include packages and base setup
    home.packages = [
      pkgs.hyprutils
      pkgs.hyprpicker
      pkgs.hyprcursor
      (lib.mkIf cfg.hyprsunset.enable pkgs.hyprsunset)
    ];

    # テーマ適用スクリプトが後から書き込む先のファイルを、空で先に用意しておく。
    # Hyprland は設定内の `source = ...` が存在しないファイルを指すとエラーを出すため、
    # 初回起動時のエラーを防ぐのが目的。
    #
    # 依存先の "mutableGeneration" は誤り（正しくは "mutableFileGeneration"）。
    # docs-ja/08-improvements.md を参照
    home.activation.createHyprConfigs = lib.hm.dag.entryAfter ["mutableGeneration"] ''
      mkdir -p "$HOME/.config/hypr/animations"
      mkdir -p "$HOME/.config/hypr/themes"
      mkdir -p "$HOME/.config/hypr/shaders"
      mkdir -p "$HOME/.config/hypr/workflows"

      touch "$HOME/.config/hypr/animations/theme.conf"
      touch "$HOME/.config/hypr/themes/colors.conf"
      touch "$HOME/.config/hypr/themes/theme.conf"
      touch "$HOME/.config/hypr/themes/wallbash.conf"

      chmod 644 "$HOME/.config/hypr/animations/theme.conf"
      chmod 644 "$HOME/.config/hypr/themes/colors.conf"
      chmod 644 "$HOME/.config/hypr/themes/theme.conf"
      chmod 644 "$HOME/.config/hypr/themes/wallbash.conf"
    '';

    home.file = {
      ".local/share/hypr/" = {
        source = "${pkgs.hyde}/Configs/.local/share/hypr/";
        recursive = true;
        force = true;
      };

      # メイン設定。overrideMain を指定すると HyDE の設定を丸ごと捨てる（非推奨）。
      # 通常は HyDE の hyprland.conf を lib.readFile で読み込み、
      # systemd 連携の 1 行を足した新しいファイルを生成する。
      #
      # source= ではなく readFile を使うのは、リンクだと中身を足せないため
      ".config/hypr/hyprland.conf" =
        if cfg.overrideMain != null
        then {
          text = cfg.overrideMain;
          force = true;
        }
        else {
          text = ''
            ${lib.readFile "${pkgs.hyde}/Configs/.config/hypr/hyprland.conf"}
            ${systemdActivation}
          '';
          force = true;
        };

      # 利用者のカスタマイズはここに入る。hyprland.conf の最後に読み込まれるので、
      # HyDE の既定値を上書きできる。通常のカスタマイズは extraConfig に書くこと
      ".config/hypr/userprefs.conf" = {
        text = cfg.extraConfig;
        force = true;
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
