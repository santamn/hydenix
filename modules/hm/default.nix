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

    # 注意: mkDefault が付いていないため、利用者側が別の値を書くと定義衝突で
    # ビルドが落ちる。型が mergeEqualOption なので「同じ値なら通る」。
    # docs-ja/08-improvements.md 参照
    home.stateVersion = "25.05";

    # let home-manager control itself
    programs.home-manager.enable = true;
  };
}
