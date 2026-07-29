# =============================================================================
# HyDE 本体モジュール
#
# pkgs.hyde（= Arch 用の HyDE を NixOS 向けに手直ししたパッケージ）の中身を、
# ホームディレクトリへ配置するのが仕事。hydenix の土台にあたる。
#
# 配置方法は 2 種類あり、使い分けが重要。
#   force = true のみ           … Nix ストアへのシンボリックリンク（読み取り専用）
#   force = true + mutable = true … 書き込み可能なコピー（HyDE が書き換えるファイル）
#
# 詳細は docs-ja/03-hyde-package.md / docs-ja/04-mutable-files.md を参照。
# =============================================================================
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.hyde;
in {
  options.hydenix.hm.hyde = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable hyde module";
    };
  };

  # TODO: review stateful files in hyde module
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      hyde # HyDE 本体（設定ファイル・スクリプト一式）
      Bibata-Modern-Ice # カーソルテーマ
      Tela-circle-dracula # アイコンテーマ
      kdePackages.kconfig # TODO: not sure if this is still needed
      wf-recorder # screen recorder for wlroots-based compositors such as sway
      pyamdgpuinfo # AMD GPU 情報（waybar の gpuinfo モジュール用）
      # 以下 4 つは HyDE 同梱版を pkgs/hyde/default.nix で削除し、Nix 版に差し替えている
      hyprquery # hyq: Hyprland の設定値を問い合わせる CLI
      hydectl # HyDE の操作 CLI
      hyde-ipc # Hyprland のイベント購読・自動化
      hyde-config # ~/.config/hyde/config.toml を解析して各設定へ反映するデーモン
    ];

    # ensures hyprland config is available in session as per hyde uwsm update
    home.sessionVariables = {
      HYPRLAND_CONFIG = "${config.xdg.dataHome}/hypr/hyprland.conf";
    };

    fonts.fontconfig.enable = true;

    # fixes cava from not initializing on boot
    # cava（音声ビジュアライザ）は設定ファイルが無いと起動に失敗するため、空ファイルを先に作る。
    # 依存先の "mutableGeneration" は誤り（正しくは "mutableFileGeneration"）。
    # docs-ja/08-improvements.md を参照
    home.activation.createCavaConfig = lib.hm.dag.entryAfter ["mutableGeneration"] ''
      mkdir -p "$HOME/.config/cava"
      touch "$HOME/.config/cava/config"
      chmod 644 "$HOME/.config/cava/config"
    '';

    home.file = {
      # Regular files (processed first)
      # wallbash（壁紙から配色を生成する仕組み）のテンプレート群。
      # HyDE のスクリプトがここへ生成物を書き込むので mutable
      ".config/hyde/wallbash" = {
        source = "${pkgs.hyde}/Configs/.config/hyde/wallbash";
        recursive = true;
        force = true;
        mutable = true;
      };

      ".config/systemd/user/hyde-config.service" = {
        text = ''
          [Unit]
          Description=HyDE Configuration Parser Service
          Documentation=https://github.com/HyDE-Project/hyde-config
          After=graphical-session.target
          PartOf=graphical-session.target

          [Service]
          Type=simple
          ExecStart=%h/.local/lib/hyde/hyde-config
          Restart=on-failure
          RestartSec=5s
          Environment="DISPLAY=:0"

          # Make sure the required directories exist
          ExecStartPre=/usr/bin/env mkdir -p %h/.config/hyde
          ExecStartPre=/usr/bin/env mkdir -p %h/.local/state/hyde

          [Install]
          WantedBy=graphical-session.target
        '';
        force = true;
      };
      ".config/systemd/user/hyde-ipc.service" = {
        source = "${pkgs.hyde}/Configs/.config/systemd/user/hyde-ipc.service";
        force = true;
      };

      ".local/bin/hyde-shell" = {
        source = "${pkgs.hyde}/Configs/.local/bin/hyde-shell";
        executable = true;
        force = true;
      };

      # HyDE のスクリプト群本体。theme.switch.sh などがここに入る
      ".local/lib/hyde" = {
        source = "${pkgs.hyde}/Configs/.local/lib/hyde";
        recursive = true;
        executable = true;
        force = true;
      };

      # 空のスクリプトで上書きして無効化している。
      # NixOS では XDG ポータルを systemd が管理するので、
      # HyDE 側のポータル再起動処理は不要（というより邪魔）
      ".local/lib/hyde/resetxdgportal.sh" = {
        text = ''
          #!/usr/bin/env bash

        '';
        executable = true;
        mutable = true;
        force = true;
      };

      ".local/share/fastfetch/presets/hyde" = {
        source = "${pkgs.hyde}/Configs/.local/share/fastfetch/presets/hyde";
        recursive = true;
        force = true;
      };
      # HyDE のデータ本体（テーマ定義・rofi アセット等）。
      # テーマ切り替えで書き換わるので mutable。
      # おかしくなったら `rm -rf ~/.local/share/hyde` で消してから rebuild すると直る
      ".local/share/hyde" = {
        source = "${pkgs.hyde}/Configs/.local/share/hyde";
        recursive = true;
        force = true;
        mutable = true;
      };
      ".local/share/wallbash/" = {
        source = "${pkgs.hyde}/Configs/.local/share/wallbash/";
        recursive = true;
        force = true;
        mutable = true;
      };
      ".local/share/waybar/includes" = {
        source = "${pkgs.hyde}/Configs/.local/share/waybar/includes";
        recursive = true;
        force = true;
      };
      ".local/share/waybar/layouts" = {
        source = "${pkgs.hyde}/Configs/.local/share/waybar/layouts";
        recursive = true;
        force = true;
      };
      ".local/share/waybar/menus" = {
        source = "${pkgs.hyde}/Configs/.local/share/waybar/menus";
        recursive = true;
        force = true;
      };
      ".local/share/waybar/modules" = {
        source = "${pkgs.hyde}/Configs/.local/share/waybar/modules";
        recursive = true;
        force = true;
      };
      ".local/share/waybar/styles" = {
        source = "${pkgs.hyde}/Configs/.local/share/waybar/styles";
        force = true;
        mutable = true;
        recursive = true;
      };
      ".config/MangoHud/MangoHud.conf" = {
        source = "${pkgs.hyde}/Configs/.config/MangoHud/MangoHud.conf";
        force = true;
      };
      ".local/share/kio/servicemenus/hydewallpaper.desktop" = {
        source = "${pkgs.hyde}/Configs/.local/share/kio/servicemenus/hydewallpaper.desktop";
        force = true;
      };
      ".local/share/kxmlgui5/dolphin/dolphinui.rc" = {
        source = "${pkgs.hyde}/Configs/.local/share/kxmlgui5/dolphin/dolphinui.rc";
        force = true;
      };

      ".config/electron-flags.conf" = {
        source = "${pkgs.hyde}/Configs/.config/electron-flags.conf";
        force = true;
      };

      ".local/share/icons/Wallbash-Icon" = {
        source = "${pkgs.hyde}/share/icons/Wallbash-Icon";
        force = true;
        recursive = true;
        mutable = true;
      };

      # stateful files
      # 以下は実行時に書き換わる「状態を持つ」ファイル群。すべて mutable
      #
      # config.toml は HyDE 全体の設定ファイル。Nix のオプションになっていないため、
      # 変更したい場合は手で編集する必要がある（オプション化は未実装）
      ".config/hyde/config.toml" = {
        source = "${pkgs.hyde}/Configs/.config/hyde/config.toml";
        force = true;
        mutable = true;
      };
      ".local/share/dolphin/view_properties/global/.directory" = {
        source = "${pkgs.hyde}/Configs/.local/share/dolphin/view_properties/global/.directory";
        force = true;
        mutable = true;
      };
      ".local/share/icons/default/index.theme" = {
        source = "${pkgs.hyde}/Configs/.local/share/icons/default/index.theme";
        force = true;
        mutable = true;
      };
      ".local/share/themes/Wallbash-Gtk" = {
        source = "${pkgs.hyde}/share/themes/Wallbash-Gtk";
        recursive = true;
        force = true;
        mutable = true;
      };
    };
  };
}
