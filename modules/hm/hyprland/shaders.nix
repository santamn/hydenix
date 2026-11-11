# =============================================================================
# 画面フィルタ（シェーダ）の選択
#
# animations / workflows と同じプリセット選択型。ただし 2 点異なる。
#   - HyDE のシェーダは ~/.config/hypr/shaders/ にすべてリンクしておき、
#     activation で `hyde-shell shaders --set <名前>` がコンパイルして有効にする
#   - overrides のキーは拡張子まで含めて書く（例: "my-filter.frag"）
# =============================================================================
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.hyprland;

  # HyDE が同梱しているシェーダ
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
          # キーは拡張子込みなので、そのままファイル名として使える
          name = ".config/hypr/shaders/${name}";
          value = lib.mkForce {
            text = content;
            force = true;
          };
        })
        cfg.shaders.overrides)
    ];

    # wallbash シェーダはテーマ切り替えが書き出す色を include するので、setTheme の後に実行する
    home.activation.setShader = lib.hm.dag.entryAfter ["mutableFileGeneration" "setTheme"] ''
      run ${pkgs.hyde}/Configs/.local/bin/hyde-shell shaders --set ${lib.escapeShellArg cfg.shaders.active}
    '';
  };
}
