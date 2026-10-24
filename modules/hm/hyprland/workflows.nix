{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.hyprland;

  # the selector matches names ignoring case, and "default" is the display name of 01-default
  presets = map lib.toLower ((import ./presets.nix).workflows ++ ["default"] ++ lib.attrNames cfg.workflows.overrides);
in {
  config = lib.mkIf (cfg.enable && cfg.workflows.enable) {
    assertions = [
      {
        assertion = lib.elem (lib.toLower cfg.workflows.active) presets;
        message = "hydenix.hm.hyprland.workflows.active: unknown workflow \"${cfg.workflows.active}\"; use one of ${lib.concatStringsSep ", " presets}";
      }
      {
        # HyDE loads the workflow with Lua's require, which reads a dot as a directory separator
        assertion = lib.all (name: builtins.match "[^./]+" name != null) (lib.attrNames cfg.workflows.overrides);
        message = "hydenix.hm.hyprland.workflows.overrides: names must not contain '.' or '/'";
      }
    ];

    # The selector lists these alongside HyDE's workflows in ~/.local/share/hypr/lua/workflows
    home.file = lib.mapAttrs' (name: text:
      lib.nameValuePair ".config/hypr/workflows/${name}.lua" {
        inherit text;
        force = true;
      })
    cfg.workflows.overrides;

    # The selector writes the state that Hyprland loads
    home.activation.setWorkflow = lib.hm.dag.entryAfter ["mutableFileGeneration"] ''
      run ${pkgs.hyde}/Configs/.local/bin/hyde-shell workflows --set ${lib.escapeShellArg cfg.workflows.active}
    '';
  };
}
