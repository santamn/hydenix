# =============================================================================
# ユーザー側（home-manager）モジュールの入口
#
# 各サブモジュールの enable は既定で `config.hydenix.hm.enable` に追従する。
# そのため利用者は `hydenix.hm.enable = true;` と書くだけで全部が有効になり、
# 不要なものだけ `hydenix.hm.firefox.enable = false;` のように個別に切れる。
# =============================================================================
{lib, ...}: {
  imports = [
    ./comma.nix
    ./dolphin.nix
    ./editors.nix
    ./fastfetch.nix
    ./firefox.nix
    ./gtk.nix
    ./hyde.nix
    ./hyprland
    ./lockscreen.nix
    ./mutable.nix
    ./notifications.nix
    ./qt.nix
    ./rofi.nix
    ./screenshots.nix
    ./shell.nix
    ./social.nix
    ./spotify.nix
    ./awww.nix
    ./terminals.nix
    ./theme.nix
    ./uwsm.nix
    ./waybar.nix
    ./wlogout.nix
    ./xdg.nix
  ];

  options.hydenix.hm = {
    enable = lib.mkEnableOption "Enable Hydenix home-manager modules globally";
  };

  config = {
    hydenix.hm.enable = lib.mkDefault false;

    # mkDefault が付いているので、利用者が自分の home-manager モジュールで
    # home.stateVersion を書けばそちらが勝つ。
    # 以前は mkDefault が無く、既定と違う値を書くと定義衝突でビルドが落ちていた
    home.stateVersion = lib.mkDefault "25.05";

    # let home-manager control itself
    programs.home-manager.enable = true;
  };
}
