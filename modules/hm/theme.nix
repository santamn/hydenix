{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.theme;

  # Helper function to find a theme package by name, returns null if not found
  findThemeByName = themeName: pkgs.hydenix-themes.${themeName} or null;

  # Filter out themes that don't have corresponding packages
  availableThemes = lib.filter (themeName: findThemeByName themeName != null) cfg.themes;

  # Icons, GTK themes and fonts of the enabled themes, bundled into one tree
  themeAssets = pkgs.hydenix-theme-assets (map findThemeByName availableThemes);
in {
  options.hydenix.hm.theme = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable theme module";
    };

    active = lib.mkOption {
      type = lib.types.str;
      default = "Catppuccin Mocha";
      description = "Active theme name";
    };

    themes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "Catppuccin Mocha"
        "Catppuccin Latte"
      ];
      description = "Available theme names";
    };
  };

  config = lib.mkIf cfg.enable {
    # The icon themes that share a name with another theme's go to the profile, which both GTK and
    # Qt search last, so ~/.local/share/icons below still provides the index.theme
    home.packages = [themeAssets.altIcons];

    # walks through the themes and creates symlinks in the hyde themes directory
    home.file = let
      # Find the package for each theme name, filtering out missing ones
      themesList = lib.filter (t: t.pkg != null) (
        map (themeName: {
          name = themeName;
          pkg = findThemeByName themeName;
        })
        availableThemes
      );

      # HyDE's theme.patch.sh unpacks into the same directories, and `recursive` links entry by
      # entry, so the theme switcher and themes imported at runtime can still write there
      assetDirs = lib.listToAttrs (
        map (
          kind:
            lib.nameValuePair ".local/share/${kind}" {
              source = "${themeAssets.main}/${kind}";
              force = true;
              recursive = true;
            }
        ) ["icons" "themes" "fonts"]
      );
    in
      lib.mkMerge (
        [assetDirs]
        ++ map (theme: {
          ".config/hyde/themes/${theme.name}" = {
            source = "${theme.pkg}/share/hyde/themes/${theme.name}";
            force = true;
            recursive = true;
            mutable = true;
          };
        })
        themesList
      );

    /*
    We require both an activation script and a service to set the theme.
    color.set.sh (run by theme.switch.sh) sources color/dconf.sh, which needs the graphical session to write dconf
    This is only an issue for the *first* rebuild, as dbus has never been started

    #TODO: this works but a more robust implementation is possible. just do what color.set.sh/color/dconf.sh does and use home.file to set the correct gtk/qt/etc options
    */

    # applies what it can before graphical.target, think of this like a "first content paint"
    home.activation.setTheme = lib.hm.dag.entryAfter ["mutableFileGeneration"] ''
      # Define path with required tools
      export PATH="${
        lib.makeBinPath (
          with pkgs; [
            awww
            killall
            hyprland
            dunst
            libnotify
            systemd
            waybar
            kitty
            gawk
            coreutils
            parallel
            imagemagick
            which
            util-linux
            dconf
          ]
        )
      }:$HOME/.local/bin:$PATH"

      if [ -n "$DRY_RUN_CMD" ]; then
        echo "Would set theme to ${cfg.active}"
      else
        # Set up logging
        LOG_FILE="$HOME/.local/state/hyde/theme-switch.log"
        mkdir -p $HOME/.local/state/hyde
        # Clear the log file before writing
        : > "$LOG_FILE"
        chmod 644 $LOG_FILE

        echo "Setting theme to ${cfg.active}..." | tee -a "$LOG_FILE"

        export LOG_LEVEL=debug

        # Run the theme switch commands with the custom runtime dir
        $HOME/.local/lib/hyde/theme.switch.sh -s "${cfg.active}" >> "$LOG_FILE" 2>&1

        echo "Theme switch completed. Log saved to $LOG_FILE" | tee -a "$LOG_FILE"
      fi
    '';

    # reapplies the theme to fix dconf
    systemd.user.services.setTheme = {
      Unit = {
        Description = "Apply Hyde theme settings (full theme switch)";
        After = [
          "graphical-session.target"
          "dbus.service"
        ];
        Wants = ["dbus.service"];
        PartOf = ["graphical-session.target"];
      };
      Service = {
        Type = "oneshot";
        ExecStart = ''
          ${config.home.homeDirectory}/.local/lib/hyde/theme.switch.sh -s "${cfg.active}" || true
        '';
        Path = with pkgs; [
          awww
          killall
          hyprland
          dunst
          libnotify
          systemd
          waybar
          kitty
          gawk
          coreutils
          parallel
          imagemagick
          which
          util-linux
          dconf
          "${config.home.homeDirectory}/.local/bin"
        ];
      };
      Install.WantedBy = ["graphical-session.target"];
    };
  };
}
