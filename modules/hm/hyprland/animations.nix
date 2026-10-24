{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.hyprland;

  # the selector matches names ignoring case
  presets = map lib.toLower ((import ./presets.nix).animations ++ lib.attrNames cfg.animations.overrides);
in {
  config = lib.mkIf (cfg.enable && cfg.animations.enable) {
    assertions = [
      {
        assertion = lib.elem (lib.toLower cfg.animations.preset) presets;
        message = "hydenix.hm.hyprland.animations.preset: unknown preset \"${cfg.animations.preset}\"; use one of ${lib.concatStringsSep ", " presets}";
      }
      {
        # HyDE loads the preset with Lua's require, which reads a dot as a directory separator
        assertion = lib.all (name: builtins.match "[^./]+" name != null) (lib.attrNames cfg.animations.overrides);
        message = "hydenix.hm.hyprland.animations.overrides: names must not contain '.' or '/'";
      }
    ];

    # The selector lists these alongside HyDE's presets in ~/.local/share/hypr/lua/animations
    home.file = lib.mapAttrs' (name: text:
      lib.nameValuePair ".config/hypr/lua/animations/${name}.lua" {
        inherit text;
        force = true;
      })
    cfg.animations.overrides;

    # The selector writes the state that Hyprland loads
    home.activation.setAnimationPreset = lib.hm.dag.entryAfter ["mutableFileGeneration"] ''
      run ${pkgs.hyde}/Configs/.local/bin/hyde-shell animations --set ${lib.escapeShellArg cfg.animations.preset}
    '';
  };
}
