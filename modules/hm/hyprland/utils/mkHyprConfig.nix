{
  config,
  pkgs,
  lib,
  ...
}: {
  name,
  extension ? "conf",
}: let
  hyprCfg = config.hydenix.hm.hyprland;
  cfg = hyprCfg.${name};
in {
  options.hydenix.hm.hyprland.${name} = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = hyprCfg.enable;
      description = "Enable ${name} configurations";
    };

    overrideConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = "Completely ${name} configuration override";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional ${name} configuration";
    };
  };

  config = lib.mkIf (hyprCfg.enable && cfg.enable) {
    warnings = lib.optional (cfg.overrideConfig != null && !hyprCfg.suppressWarnings) "hydenix.hm.hyprland.${name}.overrideConfig is overriding Hyde defaults. Note this may break hydenix, hope you know what you're doing! (set hydenix.hm.hyprland.suppressWarnings = true to hide this warning)";

    home.file.".config/hypr/${name}.${extension}" = {
      text =
        if cfg.overrideConfig != null
        then cfg.overrideConfig
        else ''
          ${lib.readFile "${pkgs.hyde}/Configs/.config/hypr/${name}.${extension}"}
          ${cfg.extraConfig}
        '';
      force = true;
      mutable = true;
    };
  };
}
