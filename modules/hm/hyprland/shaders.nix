{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.hyprland;

  standardShaders = (import ./presets.nix).shaders;
  shaders = map lib.toLower (standardShaders ++ map (lib.removeSuffix ".frag") (lib.filter (lib.hasSuffix ".frag") (lib.attrNames cfg.shaders.overrides)));
in {
  config = lib.mkIf (cfg.enable && cfg.shaders.enable) {
    assertions = [
      {
        assertion = lib.elem (lib.toLower cfg.shaders.active) shaders;
        message = "hydenix.hm.hyprland.shaders.active: unknown shader \"${cfg.shaders.active}\"; use one of ${lib.concatStringsSep ", " shaders}";
      }
    ];

    home.file = lib.mkMerge [
      # Standard shaders (generated from list)
      (lib.mkMerge [
        # Generate standard shader files from list
        (lib.listToAttrs (
          map (shader: {
            name = ".config/hypr/shaders/${shader}.frag";
            value = {
              source = "${pkgs.hyde}/Configs/.config/hypr/shaders/${shader}.frag";
              force = true;
            };
          })
          standardShaders
        ))

        # Additional shader files
        {
          ".config/hypr/shaders/wallbash.inc" = {
            force = true;
            source = "${pkgs.hyde}/Configs/.config/hypr/shaders/wallbash.inc";
          };
        }
      ])

      # Custom/override shaders; mkForce drops the file HyDE ships under the same name
      (lib.mapAttrs' (name: content: {
          name = ".config/hypr/shaders/${name}";
          value = lib.mkForce {
            text = content;
            force = true;
          };
        })
        cfg.shaders.overrides)
    ];

    home.activation.setShader = lib.hm.dag.entryAfter ["mutableFileGeneration" "setTheme"] ''
      run ${pkgs.hyde}/Configs/.local/bin/hyde-shell shaders --set ${lib.escapeShellArg cfg.shaders.active}
    '';
  };
}
