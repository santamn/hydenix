# =============================================================================
# アニメーションのプリセット選択（プリセット選択型モジュール）
#
# HyDE はプリセットを ~/.local/share/hypr/lua/animations/<名前>.lua として同梱しており、
# activation で `hyde-shell animations --set <名前>` を実行して切り替える。
# overrides に書いたものは ~/.config/hypr/lua/animations/<名前>.lua に置かれ、
# HyDE の同名プリセットより優先される（pkgs/hyde のパッチで探索順を直している）。
#
# preset に「overrides にも HyDE にも無い名前」を書くと、assertion でビルドが止まる。
# 大文字小文字は区別しない（HyDE のセレクタと同じ）
# =============================================================================
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.hyprland;

  # HyDE が同梱しているプリセット名と overrides の名前を合わせた、選べる名前の一覧
  presets = map lib.toLower ((import ./presets.nix).animations ++ lib.attrNames cfg.animations.overrides);
in {
  config = lib.mkIf (cfg.enable && cfg.animations.enable) {
    assertions = [
      {
        assertion = lib.elem (lib.toLower cfg.animations.preset) presets;
        message = "hydenix.hm.hyprland.animations.preset: unknown preset \"${cfg.animations.preset}\"; use one of ${lib.concatStringsSep ", " presets}";
      }
      {
        # require はドットをディレクトリ区切りとして読むので、名前にドットやスラッシュを許さない
        # HyDE loads the preset with Lua's require, which reads a dot as a directory separator
        assertion = lib.all (name: builtins.match "[^./]+" name != null) (lib.attrNames cfg.animations.overrides);
        message = "hydenix.hm.hyprland.animations.overrides: names must not contain '.' or '/'";
      }
    ];

    # overrides を Lua ファイルとして配置する
    home.file = lib.mapAttrs' (name: text:
      lib.nameValuePair ".config/hypr/lua/animations/${name}.lua" {
        inherit text;
        force = true;
      })
    cfg.animations.overrides;

    home.activation.setAnimationPreset = lib.hm.dag.entryAfter ["mutableFileGeneration"] ''
      run ${pkgs.hyde}/Configs/.local/bin/hyde-shell animations --set ${lib.escapeShellArg cfg.animations.preset}
    '';
  };
}
