# =============================================================================
# テーマモジュール
#
# 「テーマを選ぶ」と「その壁紙に合わせて全アプリの色が自動で揃う」を実現する。
#   1. 選択したテーマパッケージを ~/.config/hyde/themes/ 以下へ配置する
#   2. テーマに同梱のアイコン・GTK テーマ・フォントを ~/.local/share/ へ配置する
#   3. HyDE の theme.switch.sh を呼んでテーマを適用する
#
# 適用を activation script と systemd サービスの 2 段構えで行っているのが要点。
# 理由は下の setTheme のコメントを参照（詳細は docs-ja/05-theme-system.md）。
# =============================================================================
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hydenix.hm.theme;

  # Helper function to find a theme package by name, returns null if not found
  #
  # 注意: `or null` があるため、存在しないテーマ名を書いてもビルドは失敗せず、
  # そのテーマだけ警告も出ずに無視される。テーマが当たらないときはまずスペルを疑うこと。
  # 正しい名前は pkgs/hydenix-themes/default.nix のキーで確認できる
  findThemeByName = themeName: pkgs.hydenix-themes.${themeName} or null;

  # Filter out themes that don't have corresponding packages
  availableThemes = lib.filter (themeName: findThemeByName themeName != null) cfg.themes;

  # Icons, GTK themes and fonts of the enabled themes, bundled into one tree
  # 同じ名前のディレクトリを複数のテーマが持つときは、HyDE の theme.patch.sh と同じく先に書いたテーマのものを丸ごと使う。
  # 中身の違うアイコンテーマは altIcons に分けておく（pkgs/hydenix-theme-assets.nix）
  themeAssets = pkgs.hydenix-theme-assets (map findThemeByName availableThemes);
in {
  options.hydenix.hm.theme = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable theme module";
    };

    # 起動時に適用されるテーマ。themes にも含めておく必要がある
    active = lib.mkOption {
      type = lib.types.str;
      default = "Catppuccin Mocha";
      description = "Active theme name";
    };

    # インストールするテーマの一覧。
    # 書いた分だけビルド時間とディスク容量を消費するので、実利用では 2〜3 個に絞るとよい
    themes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "Catppuccin Mocha"
        "Catppuccin Latte"
      ];
      description = "Available theme names";
    };
  };

  config = lib.mkIf cfg.enable {
    # The icon themes that share a name with another theme's go to the profile, which both GTK and
    # Qt search last, so ~/.local/share/icons below still provides the index.theme
    # 名前がぶつかって ~/.local/share/icons に入れなかったアイコンテーマはプロファイルに入れる。
    # GTK も Qt もプロファイルは最後に探すので、~/.local/share/icons の index.theme が優先される
    home.packages = [themeAssets.altIcons];

    # walks through the themes and creates symlinks in the hyde themes directory
    home.file = let
      # Find the package for each theme name, filtering out missing ones
      themesList = lib.filter (t: t.pkg != null) (
        map (themeName: {
          name = themeName;
          pkg = findThemeByName themeName;
        })
        availableThemes
      );

      # アイコン・GTK テーマ・フォントを ~/.local/share/{icons,themes,fonts} に配置する。
      # recursive でエントリごとにリンクするので、ディレクトリ自体は書き込み可能なまま残り、
      # 実行時に取り込んだテーマもここに展開できる
      # HyDE's theme.patch.sh unpacks into the same directories, and `recursive` links entry by
      # entry, so the theme switcher and themes imported at runtime can still write there
      assetDirs = lib.listToAttrs (
        map (
          kind:
            lib.nameValuePair ".local/share/${kind}" {
              source = "${themeAssets.main}/${kind}";
              force = true;
              recursive = true;
            }
        ) ["icons" "themes" "fonts"]
      );
    in
      lib.mkMerge (
        [assetDirs]
        # 各テーマを ~/.config/hyde/themes/<テーマ名> へ配置する。
        # wallbash がこの中のファイルを書き換えるので mutable = true が必要
        ++ map (theme: {
          ".config/hyde/themes/${theme.name}" = {
            source = "${theme.pkg}/share/hyde/themes/${theme.name}";
            force = true;
            recursive = true;
            mutable = true;
          };
        })
        themesList
      );

    /*
    We require both an activation script and a service to set the theme.
    color.set.sh (run by theme.switch.sh) runs color/dconf.lua, which needs the graphical session to write dconf
    This is only an issue for the *first* rebuild, as dbus has never been started

    #TODO: this works but a more robust implementation is possible. just do what color.set.sh/color/dconf.lua does and use home.file to set the correct gtk/qt/etc options
    */

    /*
    【なぜ 2 か所でテーマを適用しているのか】

    theme.switch.sh から呼ばれる color.set.sh は、color/dconf.lua で dconf（GNOME 系の設定ストア）に書き込む。
    dconf は D-Bus を必要とし、D-Bus はグラフィカルセッションと一緒に起動する。
    一方 nixos-rebuild switch の activation script はセッション開始前に実行されるため、
    初回の rebuild では dconf を使う部分が必ず失敗する。

    そこで次の 2 段構えにしている。

      1. home.activation.setTheme … rebuild 時。セッション不要な部分を先に当てる
      2. setTheme.service         … ログイン後。全体を再適用して dconf の取りこぼしを直す

    うまくいかないときのログ:
      cat ~/.local/state/hyde/theme-switch.log
      journalctl --user -u setTheme.service
    */

    # applies what it can before graphical.target, think of this like a "first content paint"
    #
    # 依存先は mutable.nix が定義する "mutableFileGeneration"。
    # テーマ適用スクリプトは mutable なコピーを書き換えるので、
    # コピーが済んだ後でなければならない
    home.activation.setTheme = lib.hm.dag.entryAfter ["mutableFileGeneration"] ''
      # Define path with required tools
      # activation script は最小限の環境で動くため、必要なコマンドを明示的に PATH へ通す
      export PATH="${
        lib.makeBinPath (
          with pkgs; [
            awww
            killall
            hyprland
            hyprquery
            dunst
            libnotify
            systemd
            waybar
            kitty
            gawk
            coreutils
            parallel
            imagemagick
            which
            util-linux
            dconf
          ]
        )
      }:$HOME/.local/bin:$PATH"
      # HYPRLAND_CONFIG（hyde.lua）が見つかったときだけ、theme.switch.sh はテーマの hypr.theme を
      # Hyprland 用の Lua に変換する。無いとテーマの隙間・枠線・ぼかしがセッション内で切り替えるまで反映されない
      # theme.switch.sh turns the theme's hypr.theme into Lua for Hyprland only when it finds the Lua config here
      export HYPRLAND_CONFIG="${config.home.sessionVariables.HYPRLAND_CONFIG or ""}"

      if [[ -v DRY_RUN ]]; then
        echo "Would set theme to ${cfg.active}"
      else
        # Set up logging
        LOG_FILE="$HOME/.local/state/hyde/theme-switch.log"
        mkdir -p $HOME/.local/state/hyde
        # Clear the log file before writing
        : > "$LOG_FILE"
        chmod 644 $LOG_FILE

        echo "Setting theme to ${cfg.active}..." | tee -a "$LOG_FILE"

        export LOG_LEVEL=debug

        # waybar.py は waybar のユニット名にこの変数を使う。activation の環境には無いので、
        # 無いままだとセッションの waybar を再起動できず、2 本目を起動してしまう
        # Import the session's XDG_SESSION_DESKTOP so that waybar.py restarts the session's bar
        eval "$(systemctl --user show-environment 2>/dev/null | grep '^XDG_SESSION_DESKTOP=')"
        export XDG_SESSION_DESKTOP

        # ここはログファイルへリダイレクトする都合で run を前置できないため、
        # 上の if で dry-run のときはブロックごと飛ばしている
        # Run the theme switch commands with the custom runtime dir
        $HOME/.local/lib/hyde/theme.switch.sh -s "${cfg.active}" >> "$LOG_FILE" 2>&1

        echo "Theme switch completed. Log saved to $LOG_FILE" | tee -a "$LOG_FILE"
      fi
    '';

    # reapplies the theme to fix dconf
    # 【2 段目】ログイン後（D-Bus 起動済み）にテーマ全体を再適用し、dconf の取りこぼしを直す
    systemd.user.services.setTheme = {
      Unit = {
        Description = "Apply Hyde theme settings (full theme switch)";
        After = [
          "graphical-session.target"
          "dbus.service"
        ];
        Wants = ["dbus.service"];
        PartOf = ["graphical-session.target"];
      };
      Service = {
        Type = "oneshot";
        ExecStart = ''
          ${config.home.homeDirectory}/.local/lib/hyde/theme.switch.sh -s "${cfg.active}" || true
        '';
        Path = with pkgs; [
          awww
          killall
          hyprland
          dunst
          libnotify
          systemd
          waybar
          kitty
          gawk
          coreutils
          parallel
          imagemagick
          which
          util-linux
          dconf
          "${config.home.homeDirectory}/.local/bin"
        ];
      };
      Install.WantedBy = ["graphical-session.target"];
    };
  };
}
