# =============================================================================
# 「追記 or 置き換え」型の Hyprland 設定モジュールを生成するファクトリ関数
#
# hypridle / keybindings / monitors / nvidia / windowrules / hyprsunset は
# どれも「HyDE の <name>.conf を土台に、追記するか丸ごと置き換えるか」という
# 同一構造だったため、個別ファイルをやめて 1 つの関数にまとめてある。
#
# ■ 使い方（default.nix の imports 内）
#     (mkHyprConfig {name = "keybindings";})
#   → hydenix.hm.hyprland.keybindings.{enable,extraConfig,overrideConfig} が生えて、
#     ~/.config/hypr/keybindings.conf が配置される
#
# ■ カリー化の 2 段構造
#   1 段目 {config, pkgs, lib, ...} … default.nix から import 時に渡す
#   2 段目 {name, extension ? "conf"} … 生成したいモジュールの指定
#   返り値がモジュール（= {options, config} の属性集合）になる
# =============================================================================
{
  config,
  pkgs,
  lib,
  ...
}: {
  name,
  extension ? "conf", # pyprland だけ toml を想定していた（現在は無効化）
}: let
  hyprCfg = config.hydenix.hm.hyprland;
  cfg = hyprCfg.${name};
in {
  options.hydenix.hm.hyprland.${name} = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = hyprCfg.enable;
      description = "Enable ${name} configurations";
    };

    # 【置き換え】HyDE の設定を一切使わない。HyDE の機能をほぼ全部失うので非推奨。
    # 使うと assertions.nix が rebuild のたびに警告を出す
    overrideConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      description = "Completely ${name} configuration override";
    };

    # 【追記】HyDE の設定の後ろに足す。通常のカスタマイズはこちらを使う
    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional ${name} configuration";
    };
  };

  config = lib.mkIf (hyprCfg.enable && cfg.enable) {
    home.file.".config/hypr/${name}.${extension}" = {
      # source = ... ではなく readFile + text にしているのは、
      # リンクを張るだけでは extraConfig を後ろに足せないため
      text =
        if cfg.overrideConfig != null
        then cfg.overrideConfig
        else ''
          ${lib.readFile "${pkgs.hyde}/Configs/.config/hypr/${name}.${extension}"}
          ${cfg.extraConfig}
        '';
      force = true;
      # HyDE 側のツール（モニタ設定 UI 等）が書き換えるため mutable。
      # 副作用として、モジュールを無効化してもファイルはホームに残り続ける
      mutable = true;
    };
  };
}
