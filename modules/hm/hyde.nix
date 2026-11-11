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
      # 以下 3 つは Nix でビルドした HyDE のツール。
      # HyDE 同梱の hyq と hydectl は pkgs/hyde/default.nix で削除し、こちらに差し替えている
      hyprquery # hyq: Hyprland の設定値を問い合わせる CLI
      hydectl # HyDE の操作 CLI
      hyde-config # ~/.config/hyde/config.toml を解析して各設定へ反映するデーモン

      # fonts
      # 以前は HyDE 同梱の Source/arcs/Font_*.tar.gz を pkgs.hyde が展開していた。
      # HyDE は 2026-07-27 のリリースでフォントを同梱しなくなり、
      # Scripts/dots/archives.toml で実行時にダウンロードする方式に移ったので、同じフォントを nixpkgs から入れる。
      # MaterialDesignIcons は Nerd Fonts に含まれているので入れていない
      maple-mono.truetype
      nerd-fonts.caskaydia-cove
      nerd-fonts.jetbrains-mono
      nerd-fonts.mononoki
      noto-fonts-cjk-sans
    ];

    # HyDE の Lua 設定の入口 hyde.lua を指す。Hyprland 自身もこの変数を読んで起動する。
    # 古い ~/.local/share/hypr/hyprland.conf を指したままだと、Hyprland が空の設定を生成して
    # 素の Hyprland が起動してしまう
    # theme.switch.sh applies a theme to Hyprland only when this file is readable; HyDE's uwsm env sets the same path
    home.sessionVariables = {
      HYPRLAND_CONFIG = "${config.xdg.dataHome}/hypr/hyde.lua";
    };
    # HyDE の Lua 設定は hyprlang 版と違って ~/.local/bin を PATH に足さないので、セッション側で足す
    # Add ~/.local/bin to PATH so that HyDE's startup, keybinds, waybar and hypridle can call hyde-shell
    home.sessionPath = ["$HOME/.local/bin"];

    # 起動時の activation は /run/user/$UID ができる前に実行されることがあり、
    # HyDE のスクリプトはそこにディレクトリを作れないと終了してしまう。
    # その場合は一時ディレクトリで代用する。entryBetween で、HyDE のスクリプトを実行する 4 つの activation より前に置いている
    # hyde-shell needs a writable XDG_RUNTIME_DIR, which is missing when activation runs at boot
    home.activation.hydeRuntimeDir = lib.hm.dag.entryBetween ["setAnimationPreset" "setShader" "setTheme" "setWorkflow"] ["mutableFileGeneration"] ''
      [ -w "''${XDG_RUNTIME_DIR:-/run/user/$UID}" ] || export XDG_RUNTIME_DIR="$(mktemp -d)"
    '';

    fonts.fontconfig.enable = true;

    # fixes cava from not initializing on boot
    # cava（音声ビジュアライザ）は設定ファイルが無いと起動に失敗するため、空ファイルを先に作る。
    #
    # 依存先の名前は mutable.nix が定義する "mutableFileGeneration" と一致させること。
    # home-manager の DAG は知らない名前を黙って捨てるので、綴りを間違えると
    # 順序制約が効かないまま toposort 任せの位置で実行される。
    # run は Home Manager の関数で、dry-run のときはコマンドを実行せずに表示だけする
    home.activation.createCavaConfig = lib.hm.dag.entryAfter ["mutableFileGeneration"] ''
      run mkdir -p "$HOME/.config/cava"
      run touch "$HOME/.config/cava/config"
      run chmod 644 "$HOME/.config/cava/config"
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
