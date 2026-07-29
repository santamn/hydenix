# =============================================================================
# テーマモジュール
#
# 「テーマを選ぶ」と「その壁紙に合わせて全アプリの色が自動で揃う」を実現する。
#   1. 選択したテーマパッケージを ~/.config/hyde/themes/ 以下へ配置する
#   2. HyDE の theme.switch.sh を呼んでテーマを適用する
#
# 適用を activation script と systemd サービスの 3 段構えで行っているのが要点。
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
  # そのテーマだけ黙って無視される。テーマが当たらないときはまずスペルを疑うこと。
  # 正しい名前は pkgs/hydenix-themes/default.nix のキーで確認できる
  findThemeByName = themeName: pkgs.hydenix-themes.${themeName} or null;

  # Filter out themes that don't have corresponding packages
  availableThemes = lib.filter (themeName: findThemeByName themeName != null) cfg.themes;
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
    # Create a combined theme package using symlinkJoin with only selected themes
    # symlinkJoin: 複数パッケージの中身を 1 つのディレクトリにリンクで束ねる
    home.packages = [
      (pkgs.symlinkJoin {
        name = "hydenix-themes";
        paths = lib.filter (p: p != null) (map findThemeByName availableThemes);
        meta = {
          description = "Combined HyDE themes package";
          platforms = pkgs.lib.platforms.all;
        };
      })
    ];

    # walks through the themes and creates symlinks in the hyde themes directory
    # 各テーマを ~/.config/hyde/themes/<テーマ名> へ配置する。
    # wallbash がこの中のファイルを書き換えるので mutable = true が必要
    home.file = let
      # Find the package for each theme name, filtering out missing ones
      themesList = lib.filter (t: t.pkg != null) (
        map (themeName: {
          name = themeName;
          pkg = findThemeByName themeName;
        })
        availableThemes
      );
    in
      lib.mkMerge (
        map (theme: {
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
    theme.set.sh uses dconf partially to set vars, which requires graphical targets to run
    This is only an issue for the *first* rebuild, as dbus has never been started

    #TODO: this works but a more robust implementation is possible. just do what theme.set.sh/dconf.set.sh does and use home.file to set the correct gtk/qt/etc options
    */
    /*
    【なぜ 3 か所でテーマを適用しているのか】

    theme.switch.sh は内部で dconf（GNOME 系の設定ストア）を使う。
    dconf は D-Bus を必要とし、D-Bus はグラフィカルセッションと一緒に起動する。
    一方 nixos-rebuild switch の activation script はセッション開始前に走るため、
    初回の rebuild では dconf を使う部分が必ず失敗する。

    そこで次の 3 段構えにしている。

      1. home.activation.setTheme   … rebuild 時。セッション不要な部分を先に当てる
      2. setThemeDconf.service      … ログイン後。dconf 設定を反映
      3. setTheme.service           … dconf の後。全体を再適用して取りこぼしを直す

    うまくいかないときのログ:
      cat ~/.local/state/hyde/theme-switch.log
      journalctl --user -u setTheme.service
    */

    # applies what it can before graphical.target, think of this like a "first content paint"
    #
    # 注意: 依存先の "mutableGeneration" は存在しないエントリ名。
    # 正しくは "mutableFileGeneration"（mutable.nix が定義）。
    # home-manager は不明な依存名を黙って無視するので順序制約が効いていない。
    # 詳細と修正方針は docs-ja/08-improvements.md を参照
    home.activation.setTheme = lib.hm.dag.entryAfter ["mutableGeneration"] ''
      # Define path with required tools
      # activation script は最小限の環境で動くため、必要なコマンドを明示的に PATH へ通す
      export PATH="${
        lib.makeBinPath (
          with pkgs; [
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
          ]
        )
      }:$HOME/.local/bin:$PATH"

      # Set up logging
      LOG_FILE="$HOME/.local/state/hyde/theme-switch.log"
      mkdir -p $HOME/.local/state/hyde
      # Clear the log file before writing
      : > "$LOG_FILE"
      chmod 644 $LOG_FILE

      echo "Setting theme to ${cfg.active}..." | tee -a "$LOG_FILE"

      export LOG_LEVEL=debug

      # Run the theme switch commands with the custom runtime dir
      # 注: ここは $DRY_RUN_CMD を使っていないので dry-activate でも実際に走ってしまう
      $HOME/.local/lib/hyde/theme.switch.sh -s "${cfg.active}" >> "$LOG_FILE" 2>&1

      echo "Theme switch completed. Log saved to $LOG_FILE" | tee -a "$LOG_FILE"
    '';

    # sets dconf settings correctly
    # 【2 段目】ログイン後（D-Bus 起動済み）に dconf 設定を反映する
    systemd.user.services.setThemeDconf = {
      Unit = {
        Description = "Apply Hyde theme dconf settings";
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
          ${config.home.homeDirectory}/.local/lib/hyde/dconf.set.sh
        '';
        Path = with pkgs; [
          dconf
          glib
          hyprland
          util-linux
          which
          coreutils
          imagemagick
          gawk
          parallel
          awww
          waybar
          kitty
          dunst
          libnotify
          "${config.home.homeDirectory}/.local/bin"
        ];
      };
      Install.WantedBy = ["graphical-session.target"];
    };

    # reapplies the theme to fix dconf
    # 【3 段目】dconf 反映後にテーマ全体を再適用し、取りこぼしを修正する
    systemd.user.services.setTheme = {
      Unit = {
        Description = "Apply Hyde theme settings (full theme switch)";
        After = [
          "graphical-session.target"
          "dbus.service"
          "setThemeDconf.service"
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
