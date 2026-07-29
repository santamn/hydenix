# =============================================================================
# システム側（NixOS）モジュールの入口
#
# hm 側と同じく、各サブモジュールの enable は `config.hydenix.enable` に追従する。
# ただし nix.nix / sddm.nix / system.nix の 3 つだけは既定値が `true` で固定されており、
# hydenix.enable = false にしても有効なままになる点に注意（本家から続く仕様）。
# =============================================================================
{
  lib,
  config,
  ...
}: let
  cfg = config.hydenix;

  # timezone に空白が含まれていないことを検査する独自型。
  # addCheck で既存の str 型に述語を足し、description を差し替えている
  nospace = str: lib.filter (c: c == " ") (lib.stringToCharacters str) == [];
  timezoneType =
    lib.types.nullOr (lib.types.addCheck lib.types.str nospace)
    // {
      description = "null or string without spaces";
    };
in {
  imports = [
    ./audio.nix
    ./boot.nix
    ./hardware.nix
    ./network.nix
    ./nix.nix
    ./sddm.nix
    ./system.nix
    ./gaming.nix
  ];

  options.hydenix = {
    enable = lib.mkEnableOption "Enable Hydenix modules globally";

    hostname = lib.mkOption {
      type = lib.types.str;
      description = "The name of the machine.";
      example = "hydenix";
      default = config.system.nixos.distroId;
    };

    timezone = lib.mkOption {
      type = timezoneType;
      description = "The time zone used when displaying times and dates.";
      example = "America/Vancouver";
      default = null;
    };

    locale = lib.mkOption {
      type = lib.types.str;
      description = "The default locale.";
      example = "en_CA.UTF-8";
      default = "en_US.UTF-8";
    };
  };

  config = {
    hydenix.enable = lib.mkDefault false;

    # Configuration for variables (only applied when hydenix is enabled)
    #
    # mkDefault が付いているので、利用者が configuration.nix 側で
    # networking.hostName 等を直接書いた場合はそちらが優先される。
    # 多ホスト構成（ホストごとに hostName を変える）と綺麗に噛み合う。
    # 本家には mkDefault が無く、必須アサーションもあった
    time.timeZone = lib.mkIf cfg.enable (lib.mkDefault cfg.timezone);
    i18n.defaultLocale = lib.mkIf cfg.enable (lib.mkDefault cfg.locale);
    networking.hostName = lib.mkIf cfg.enable (lib.mkDefault cfg.hostname);

    # 注意: こちらは mkDefault が無い。利用者側が別の値を書くと定義衝突になる。
    # docs-ja/08-improvements.md 参照
    system.stateVersion = "25.05";
  };
}
