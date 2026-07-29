# 壁紙デーモン awww。
# 本家では swww を使っていたが、このフォークでは awww に差し替えられている。
# テーマ適用スクリプトが壁紙を切り替えるときに呼ぶので、theme.nix の PATH にも入っている。
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.awww;
in {
  options.hydenix.hm.awww = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable awww wallpaper daemon";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      (lib.mkIf cfg.enable awww) # wallpaper daemon for wayland
    ];
  };
}
