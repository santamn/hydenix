# =============================================================================
# 画面フィルタ（シェーダ）の選択
#
# animations / workflows と同じプリセット選択型。ただし 2 点異なる。
#   - 選択結果は .conf ではなく shaders.conf 内の変数として書き出される
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
  standardShaders = [
    "blue-light-filter"
    "color-vision"
    "custom"
    "disable"
    "grayscale"
    "invert-colors"
    "oled"
    "oled-saver"
    "paper"
    "vibrance"
    "wallbash"
  ];
in {
  config = lib.mkIf (cfg.enable && cfg.shaders.enable) {
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
          ".config/hypr/shaders/.compiled.cache.glsl" = {
            source = "${pkgs.hyde}/Configs/.config/hypr/shaders/.compiled.cache.glsl";
            force = true;
            mutable = true;
          };
          ".config/hypr/shaders.conf" = {
            text = ''
              # name of the shader
              $SCREEN_SHADER = "${cfg.shaders.active}"
              # path to the shader
              $SCREEN_SHADER_PATH = "$XDG_CONFIG_HOME/hypr/shaders/${cfg.shaders.active}.frag"
              # path to the compiled shader // override this in '../hyde/config.toml'
              $SCREEN_SHADER_COMPILED = $XDG_CONFIG_HOME/hypr/shaders/.compiled.cache.glsl
            '';
            force = true;
            mutable = true;
          };
          ".config/hypr/shaders/wallbash.inc" = {
            force = true;
            source = "${pkgs.hyde}/Configs/.config/hypr/shaders/wallbash.inc";
          };
        }
      ])

      # Custom/override shaders
      # overrides のキーは拡張子込みで書く（例: "my-filter.frag"）ので、
      # そのままファイル名として使える
      (lib.mapAttrs' (name: content: {
          name = ".config/hypr/shaders/${name}";
          value = {
            text = content;
            force = true;
          };
        })
        cfg.shaders.overrides)
    ];
  };
}
