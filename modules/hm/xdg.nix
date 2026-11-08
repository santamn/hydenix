{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.xdg;
in {
  options.hydenix.hm.xdg = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable XDG base directory specification";
    };
  };

  config = lib.mkIf cfg.enable {
    xdg = {
      enable = true;

      portal = {
        enable = true;
        extraPortals = with pkgs; [
          pkgs.xdg-desktop-portal-hyprland
          xdg-desktop-portal-gtk
          xdg-desktop-portal
        ];
        xdgOpenUsePortal = true;
        configPackages = with pkgs; [
          pkgs.xdg-desktop-portal-hyprland
          xdg-desktop-portal-gtk
          xdg-desktop-portal
        ];
      };

      mimeApps = {
        enable = true;
      };

      userDirs = {
        enable = true;
        createDirectories = true;
        # export XDG_DESKTOP_DIR and friends; leaving it unset warns when home.stateVersion < 26.05
        setSessionVariables = true;

        # Define standard XDG user directories
        desktop = "${config.home.homeDirectory}/Desktop";
        documents = "${config.home.homeDirectory}/Documents";
        download = "${config.home.homeDirectory}/Downloads";
        music = "${config.home.homeDirectory}/Music";
        pictures = "${config.home.homeDirectory}/Pictures";
        publicShare = "${config.home.homeDirectory}/Public";
        templates = "${config.home.homeDirectory}/Templates";
        videos = "${config.home.homeDirectory}/Videos";
      };

      # Define standard XDG base directories
      cacheHome = "${config.home.homeDirectory}/.cache";
      configHome = "${config.home.homeDirectory}/.config";
      dataHome = "${config.home.homeDirectory}/.local/share";
      stateHome = "${config.home.homeDirectory}/.local/state";
    };

    # Set environment variables
    home.sessionVariables = {
      # Base XDG directories
      XDG_CACHE_HOME = config.xdg.cacheHome;
      XDG_CONFIG_HOME = config.xdg.configHome;
      XDG_DATA_HOME = config.xdg.dataHome;
      XDG_STATE_HOME = config.xdg.stateHome;
      XDG_RUNTIME_DIR = "/run/user/$(id -u)";

      # Additional XDG-related variables
      LESSHISTFILE = "/tmp/less-hist";
      PARALLEL_HOME = "${config.xdg.configHome}/parallel";
      SCREENRC = "${config.xdg.configHome}/screen/screenrc";
    };
  };
}
