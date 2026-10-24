{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.hyprland;
  mkHyprConfig = import ./utils/mkHyprConfig.nix {inherit lib pkgs config;};

  variables = builtins.concatStringsSep " " cfg.systemd.variables;
  extraCommands = builtins.concatStringsSep " " (map (f: "&& ${f}") cfg.systemd.extraCommands);
  # Lua's exec-once: Hyprland fires hyprland.start once, and a reload drops the handler without firing it again
  systemdActivation = ''
    hl.on("hyprland.start", function()
      hl.exec_cmd(${builtins.toJSON "${pkgs.dbus}/bin/dbus-update-activation-environment --systemd ${variables} ${extraCommands}"})
    end)
  '';

  # A syntax error skips the whole file, including the hyprland.start handler, and Hyprland reports it only at login
  luaFile = text:
    pkgs.writeTextFile {
      name = "hyprland.lua";
      inherit text;
      checkPhase = ''
        ${pkgs.lua5_5}/bin/luac -p "$target" || {
          cat -n "$target" >&2
          echo "hydenix.hm.hyprland: hyprland.lua above is not valid Lua; since HyDE v26.08.21, extraConfig and overrideMain take Lua (see HyDE's MIGRATION-LUA.md)" >&2
          exit 1
        }
      '';
    };
in {
  imports = [
    ./animations.nix
    ./options.nix
    ./shaders.nix
    ./workflows.nix
    (mkHyprConfig {name = "hypridle";})
    (mkHyprConfig {name = "hyprlock";})
    # (mkHyprConfig {name = "pyprland"; extension = "toml";})
    (mkHyprConfig {name = "hyprsunset";})
  ];

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (cfg.overrideMain != null && !cfg.suppressWarnings) "hydenix.hm.hyprland.overrideMain is overriding hydenix's hyprland.lua. Note this may break hydenix, hope you know what you're doing! (set hydenix.hm.hyprland.suppressWarnings = true to hide this warning)";

    # Always include packages and base setup
    home.packages = [
      pkgs.hyprutils
      pkgs.hyprpicker
      pkgs.hyprcursor
      (lib.mkIf cfg.hyprlock.enable pkgs.hyprlock)
      (lib.mkIf cfg.hyprsunset.enable pkgs.hyprsunset)
    ];

    # hyprlock sources the colors wallbash writes here
    home.activation.createHyprConfigs = lib.hm.dag.entryAfter ["mutableFileGeneration"] ''
      run mkdir -p "$HOME/.config/hypr/themes"
      run touch "$HOME/.config/hypr/themes/colors.conf"
      run chmod 644 "$HOME/.config/hypr/themes/colors.conf"
    '';

    home.file = {
      ".local/share/hypr/" = {
        source = "${pkgs.hyde}/Configs/.local/share/hypr/";
        recursive = true;
        force = true;
      };

      # The user layer that hyde.lua, HyDE's entry point, loads after its own config
      ".config/hypr/hyprland.lua" =
        if cfg.overrideMain != null
        then {
          source = luaFile cfg.overrideMain;
          force = true;
        }
        else {
          source = luaFile ''
            -- Hyprland starts from this file only when started without -c or HYPRLAND_CONFIG.
            -- hyde.lua then loads this file again as its user layer, so stop here instead of running it twice.
            if not hyde then
              dofile((os.getenv("XDG_DATA_HOME") or os.getenv("HOME") .. "/.local/share") .. "/hypr/hyde.lua")
              return
            end

            ${lib.optionalString cfg.systemd.enable systemdActivation}
            ${cfg.extraConfig}
          '';
          force = true;
        };

      ".config/hypr/hyprlock" = lib.mkIf cfg.hyprlock.enable {
        source = "${pkgs.hyde}/Configs/.config/hypr/hyprlock";
        recursive = true;
        force = true;
        mutable = true;
      };
    };

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
