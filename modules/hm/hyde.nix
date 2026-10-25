{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.hyde;
in {
  options.hydenix.hm.hyde = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable hyde module";
    };
  };

  # TODO: review stateful files in hyde module
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      hyde
      Bibata-Modern-Ice
      Tela-circle-dracula
      kdePackages.kconfig # TODO: not sure if this is still needed
      wf-recorder # screen recorder for wlroots-based compositors such as sway
      pyamdgpuinfo
      hyprquery
      hydectl
      hyde-config

      # fonts
      maple-mono.truetype
      nerd-fonts.caskaydia-cove
      nerd-fonts.jetbrains-mono
      nerd-fonts.mononoki
      noto-fonts-cjk-sans
    ];

    # theme.switch.sh applies a theme to Hyprland only when this file is readable; HyDE's uwsm env sets the same path
    home.sessionVariables = {
      HYPRLAND_CONFIG = "${config.xdg.dataHome}/hypr/hyde.lua";
    };
    # HyDE's binds and scripts run hyde-shell by name
    home.sessionPath = ["$HOME/.local/bin"];

    # hyde-shell needs a writable XDG_RUNTIME_DIR, which is missing when activation runs at boot
    home.activation.hydeRuntimeDir = lib.hm.dag.entryBetween ["setAnimationPreset" "setShader" "setTheme" "setWorkflow"] ["mutableFileGeneration"] ''
      [ -w "''${XDG_RUNTIME_DIR:-/run/user/$UID}" ] || export XDG_RUNTIME_DIR="$(mktemp -d)"
    '';

    fonts.fontconfig.enable = true;

    # fixes cava from not initializing on boot
    home.activation.createCavaConfig = lib.hm.dag.entryAfter ["mutableFileGeneration"] ''
      run mkdir -p "$HOME/.config/cava"
      run touch "$HOME/.config/cava/config"
      run chmod 644 "$HOME/.config/cava/config"
    '';

    home.file = {
      # Regular files (processed first)
      ".config/hyde/wallbash" = {
        source = "${pkgs.hyde}/Configs/.config/hyde/wallbash";
        recursive = true;
        force = true;
        mutable = true;
      };

      ".local/bin/hyde-shell" = {
        source = "${pkgs.hyde}/Configs/.local/bin/hyde-shell";
        executable = true;
        force = true;
      };

      ".local/lib/hyde" = {
        source = "${pkgs.hyde}/Configs/.local/lib/hyde";
        recursive = true;
        executable = true;
        force = true;
      };

      ".local/lib/hyde/resetxdgportal.sh" = {
        text = ''
          #!/usr/bin/env bash

        '';
        executable = true;
        mutable = true;
        force = true;
      };

      ".local/share/fastfetch/presets/hyde" = {
        source = "${pkgs.hyde}/Configs/.local/share/fastfetch/presets/hyde";
        recursive = true;
        force = true;
      };
      ".local/share/hyde" = {
        source = "${pkgs.hyde}/Configs/.local/share/hyde";
        recursive = true;
        force = true;
        mutable = true;
      };
      ".local/share/wallbash/" = {
        source = "${pkgs.hyde}/Configs/.local/share/wallbash/";
        recursive = true;
        force = true;
        mutable = true;
      };
      ".local/share/waybar/includes" = {
        source = "${pkgs.hyde}/Configs/.local/share/waybar/includes";
        recursive = true;
        force = true;
      };
      ".local/share/waybar/layouts" = {
        source = "${pkgs.hyde}/Configs/.local/share/waybar/layouts";
        recursive = true;
        force = true;
      };
      ".local/share/waybar/menus" = {
        source = "${pkgs.hyde}/Configs/.local/share/waybar/menus";
        recursive = true;
        force = true;
      };
      ".local/share/waybar/modules" = {
        source = "${pkgs.hyde}/Configs/.local/share/waybar/modules";
        recursive = true;
        force = true;
      };
      ".local/share/waybar/styles" = {
        source = "${pkgs.hyde}/Configs/.local/share/waybar/styles";
        force = true;
        mutable = true;
        recursive = true;
      };
      ".config/MangoHud/MangoHud.conf" = {
        source = "${pkgs.hyde}/Configs/.config/MangoHud/MangoHud.conf";
        force = true;
      };
      ".local/share/kio/servicemenus/hydewallpaper.desktop" = {
        source = "${pkgs.hyde}/Configs/.local/share/kio/servicemenus/hydewallpaper.desktop";
        force = true;
      };
      ".local/share/kxmlgui5/dolphin/dolphinui.rc" = {
        source = "${pkgs.hyde}/Configs/.local/share/kxmlgui5/dolphin/dolphinui.rc";
        force = true;
      };

      ".config/electron-flags.conf" = {
        source = "${pkgs.hyde}/Configs/.config/electron-flags.conf";
        force = true;
      };

      ".local/share/icons/Wallbash-Icon" = {
        source = "${pkgs.hyde}/share/icons/Wallbash-Icon";
        force = true;
        recursive = true;
        mutable = true;
      };

      # stateful files
      ".config/hyde/config.toml" = {
        source = "${pkgs.hyde}/Configs/.config/hyde/config.toml";
        force = true;
        mutable = true;
      };
      ".local/share/dolphin/view_properties/global/.directory" = {
        source = "${pkgs.hyde}/Configs/.local/share/dolphin/view_properties/global/.directory";
        force = true;
        mutable = true;
      };
      ".local/share/icons/default/index.theme" = {
        source = "${pkgs.hyde}/Configs/.local/share/icons/default/index.theme";
        force = true;
        mutable = true;
      };
      ".local/share/themes/Wallbash-Gtk" = {
        source = "${pkgs.hyde}/share/themes/Wallbash-Gtk";
        recursive = true;
        force = true;
        mutable = true;
      };
    };
  };
}
