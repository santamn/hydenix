# =============================================================================
# ワークフロー（用途別の Hyprland 設定プリセット）の選択
#
# animations.nix と同じ「プリセット選択型」だが、1 点だけ違いがある。
# 標準プリセットに無い名前を overrides に書くと、
# 新規ワークフローとしても配置される（末尾の mapAttrs' + filterAttrs の処理）。
# =============================================================================
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.hyprland;

  # HyDE が同梱している標準ワークフロー
  workflowPresets = [
    "default"
    "editing"
    "gaming"
    "powersaver"
    "snappy"
  ];
in {
  config = lib.mkIf (cfg.enable && cfg.workflows.enable) {
    home.file = lib.mkMerge [
      # Active workflow
      {
        ".config/hypr/workflows.conf" =
          if cfg.workflows.overrides ? ${cfg.workflows.active}
          then {
            text = cfg.workflows.overrides.${cfg.workflows.active};
            force = true;
            mutable = true;
          }
          else {
            source = "${pkgs.hyde}/Configs/.config/hypr/workflows/${cfg.workflows.active}.conf";
            force = true;
            mutable = true;
          };
      }

      # All workflow presets (with overrides)
      (lib.listToAttrs (
        map (workflow: {
          name = ".config/hypr/workflows/${workflow}.conf";
          value =
            if cfg.workflows.overrides ? ${workflow}
            then {
              text = cfg.workflows.overrides.${workflow};
              force = true;
            }
            else {
              source = "${pkgs.hyde}/Configs/.config/hypr/workflows/${workflow}.conf";
              force = true;
            };
        })
        workflowPresets
      ))

      # Custom workflows (exclude the standard presets)
      # 標準プリセット以外の overrides を、新しいワークフローとして追加配置する。
      # filterAttrs で標準プリセットを除外し、mapAttrs' でキーをパスに変換している
      (lib.mapAttrs' (name: content: {
        name = ".config/hypr/workflows/${name}.conf";
        value = {
          text = content;
          force = true;
        };
      }) (lib.filterAttrs (name: _: !(lib.elem name workflowPresets)) cfg.workflows.overrides))
    ];
  };
}
