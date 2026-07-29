# UWSM (Universal Wayland Session Manager) 用の環境変数ファイル配置。
#
# UWSM は Wayland セッションを systemd の管理下に置く仕組みで、
# 「ログイン → セッション起動 → graphical-session.target」の流れを作る。
# テーマ適用サービス（theme.nix）はこの target を起点に動く。
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.uwsm;
in {
  options.hydenix.hm.uwsm = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable uwsm module";
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = {
      ".config/uwsm/env" = {
        source = "${pkgs.hyde}/Configs/.config/uwsm/env";
        force = true;
      };
      ".config/uwsm/env.d/00-hyde.sh" = {
        source = "${pkgs.hyde}/Configs/.config/uwsm/env.d/00-hyde.sh";
        force = true;
      };
      ".config/uwsm/env.d/01-gpu.sh" = {
        source = "${pkgs.hyde}/Configs/.config/uwsm/env.d/01-gpu.sh";
        force = true;
      };
      ".config/uwsm/env-hyprland" = {
        source = "${pkgs.hyde}/Configs/.config/uwsm/env-hyprland";
        force = true;
      };
      ".config/uwsm/env-hyprland.d/00-hyde.sh" = {
        source = "${pkgs.hyde}/Configs/.config/uwsm/env-hyprland.d/00-hyde.sh";
        force = true;
      };
    };
  };
}
