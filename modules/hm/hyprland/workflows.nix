# =============================================================================
# ワークフロー（用途別の Hyprland 設定プリセット）の選択
#
# animations.nix と同じプリセット選択型。HyDE の同梱分は
# ~/.local/share/hypr/lua/workflows/<名前>.lua にあり、activation で
# `hyde-shell workflows --set <名前>` を実行して切り替える。
# overrides に書いたものは ~/.config/hypr/workflows/<名前>.lua に置かれ、
# 標準に無い名前なら新しいワークフローとして選べるようになる。
# =============================================================================
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.hyprland;

  # "default" は 01-default.lua の表示名。HyDE のセレクタはファイル名でも表示名でも引ける
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

    # overrides を Lua ファイルとして配置する
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
