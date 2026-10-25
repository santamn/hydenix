{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.hyprland;

  presets = map lib.toLower ((import ./presets.nix).workflows ++ ["default"] ++ lib.attrNames cfg.workflows.overrides);
in {
  config = lib.mkIf (cfg.enable && cfg.workflows.enable) {
    assertions = [
      {
        assertion = lib.elem (lib.toLower cfg.workflows.active) presets;
        message = "hydenix.hm.hyprland.workflows.active: unknown workflow \"${cfg.workflows.active}\"; use one of ${lib.concatStringsSep ", " presets}";
      }
      {
        assertion = lib.all (name: builtins.match "[^./]+" name != null) (lib.attrNames cfg.workflows.overrides);
        message = "hydenix.hm.hyprland.workflows.overrides: names must not contain '.' or '/'";
      }
    ];

    home.file = lib.mapAttrs' (name: text:
      lib.nameValuePair ".config/hypr/workflows/${name}.lua" {
        inherit text;
        force = true;
      })
    cfg.workflows.overrides;

    home.activation.setWorkflow = lib.hm.dag.entryAfter ["mutableFileGeneration"] ''
      run ${pkgs.hyde}/Configs/.local/bin/hyde-shell workflows --set ${lib.escapeShellArg cfg.workflows.active}
    '';
  };
}
