# =============================================================================
# override 系オプションの検証と警告
#
#   assertions … 「null ではないが空文字」という危険な設定を弾いてビルドを止める
#   warnings   … override を使っていること自体を rebuild のたびに知らせる
#
# override は HyDE の既定設定を丸ごと捨てる操作なので、事故を防ぐための安全網。
# 自覚して使うなら suppressWarnings = true; で警告だけ黙らせられる。
#
# 注意: フォークで追加された hyprsunset はここに含まれていない
# =============================================================================
{
  config,
  lib,
  ...
}: let
  cfg = config.hydenix.hm.hyprland;

  # Collect all active overrides
  # optionalString は「条件が偽なら空文字」を返すので、
  # filter で空文字を落とすと「有効になっている override の名前一覧」が得られる
  activeOverrides = lib.filter (x: x != null && x != "") [
    (lib.optionalString (cfg.hypridle.overrideConfig != null) "hypridle.overrideConfig")
    (lib.optionalString (cfg.keybindings.overrideConfig != null) "keybindings.overrideConfig")
    (lib.optionalString (cfg.windowrules.overrideConfig != null) "windowrules.overrideConfig")
    (lib.optionalString (cfg.nvidia.overrideConfig != null) "nvidia.overrideConfig")
    (lib.optionalString (cfg.monitors.overrideConfig != null) "monitors.overrideConfig")
    (lib.optionalString (cfg.overrideMain != null) "overrideMain")
  ];
in {
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.hypridle.overrideConfig == null || cfg.hypridle.overrideConfig != "";
        message = "hydenix.hm.hyprland.hypridle.overrideConfig is set but empty. This will override Hyde defaults and may break the system. Set to null to use Hyde defaults or provide valid configuration.";
      }
      {
        assertion = cfg.keybindings.overrideConfig == null || cfg.keybindings.overrideConfig != "";
        message = "hydenix.hm.hyprland.keybindings.overrideConfig is set but empty. This will override Hyde defaults and may break the system. Set to null to use Hyde defaults or provide valid configuration.";
      }
      {
        assertion = cfg.windowrules.overrideConfig == null || cfg.windowrules.overrideConfig != "";
        message = "hydenix.hm.hyprland.windowrules.overrideConfig is set but empty. This will override Hyde defaults and may break the system. Set to null to use Hyde defaults or provide valid configuration.";
      }
      {
        assertion = cfg.nvidia.overrideConfig == null || cfg.nvidia.overrideConfig != "";
        message = "hydenix.hm.hyprland.nvidia.overrideConfig is set but empty. This will override Hyde defaults and may break the system. Set to null to use Hyde defaults or provide valid configuration.";
      }
      {
        assertion = cfg.monitors.overrideConfig == null || cfg.monitors.overrideConfig != "";
        message = "hydenix.hm.hyprland.monitors.overrideConfig is set but empty. This will override Hyde defaults and may break the system. Set to null to use Hyde defaults or provide valid configuration.";
      }
      {
        assertion = cfg.overrideMain == null || cfg.overrideMain != "";
        message = "hydenix.hm.hyprland.overrideMain is set but empty. This will completely override Hyde's hyprland.conf and may break the system. Set to null to use Hyde defaults or provide valid configuration.";
      }
    ];

    warnings = lib.optionals (cfg.enable && activeOverrides != [] && !cfg.suppressWarnings) [
      "hydenix.hm.hyprland: The following configs are overriding Hyde defaults. Note this may break hydenix, hope you know what you're doing! (set suppressWarnings = true to hide this warning): ${lib.concatStringsSep ", " activeOverrides}"
    ];
  };
}
