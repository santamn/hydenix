# =============================================================================
# アニメーションのプリセット選択（プリセット選択型モジュール）
#
# 「候補ファイルを全部 ~/.config/hypr/animations/ に置いておき、
#   そのうち 1 つを animations.conf として有効にする」という構造。
# 全部置いておくのは、実行中に HyDE 側の機能で切り替えられるようにするため。
#
# preset に「overrides にも HyDE にも無い名前」を書くと参照先ファイルが存在せず
# ビルドが失敗する（テーマ名と違い、黙って無視はされない）
# =============================================================================
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.hyprland;

  # HyDE が同梱しているプリセット名の一覧
  animationPresets = [
    "LimeFrenzy"
    "classic"
    "diablo-1"
    "diablo-2"
    "disable"
    "dynamic"
    "end4"
    "fast"
    "high"
    "ja"
    "me-1"
    "me-2"
    "minimal-1"
    "minimal-2"
    "moving"
    "optimized"
    "standard"
    "vertical"
    "theme"
  ];
in {
  config = lib.mkIf (cfg.enable && cfg.animations.enable) {
    home.file = lib.mkMerge [
      # Active animation preset
      # (1) 現在有効なプリセット → animations.conf
      #     判定は「overrides にそのキーがあるか」だけで行う
      {
        ".config/hypr/animations.conf" =
          if cfg.animations.overrides ? ${cfg.animations.preset}
          then {
            text = ''
              ${cfg.animations.overrides.${cfg.animations.preset}}
              ${cfg.animations.extraConfig}
            '';
            force = true;
            mutable = true;
          }
          else {
            source = "${pkgs.hyde}/Configs/.config/hypr/animations/${cfg.animations.preset}.conf";
            force = true;
            mutable = true;
          };
      }

      # All animation presets (with overrides)
      # (2) 全プリセット → animations/<名前>.conf
      #     実行中に切り替えられるよう、選ばれなかったものも配置しておく
      (lib.listToAttrs (
        map (preset: {
          name = ".config/hypr/animations/${preset}.conf";
          value =
            if cfg.animations.overrides ? ${preset}
            then {
              text = cfg.animations.overrides.${preset};
              force = true;
            }
            else {
              source = "${pkgs.hyde}/Configs/.config/hypr/animations/${preset}.conf";
              force = true;
            };
        })
        animationPresets
      ))
    ];
  };
}
