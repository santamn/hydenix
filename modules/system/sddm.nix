# ログイン画面（SDDM）。
#
# 重要: ログイン画面は home-manager の設定が適用される「前」に表示される。
# そのためカーソルテーマなどはシステム側（ここ）で指定する必要がある。
#
# 注意: enable の既定値が `true` 固定。`hydenix.enable = false` にしても有効なまま。
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.sddm;
in {
  options.hydenix.sddm = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable sddm module";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      hyde
      Bibata-Modern-Ice
      sddm-astronaut
    ];

    # ログイン画面は home-manager 適用前に出るため、
    # カーソルテーマはここ（システム側）で指定しないと効かない
    # Add this section to ensure cursor theme is properly loaded
    environment.sessionVariables = {
      XCURSOR_THEME = "Bibata-Modern-Ice";
      XCURSOR_SIZE = "24";
    };

    services.displayManager.sddm = {
      enable = true;
      theme = "sddm-astronaut-theme";
      wayland = {
        enable = true;
      };
      extraPackages = with pkgs.kdePackages; [
        qtsvg
        qtmultimedia
        qtvirtualkeyboard
      ];
      settings = {
        Theme = {
          CursorTheme = "Bibata-Modern-Ice";
          CursorSize = "24";
        };
        General = {
          # Set default session globally
          DefaultSession = "hyprland.desktop";
        };
        Wayland = {
          EnableHiDPI = true;
        };
      };
    };
  };
}
