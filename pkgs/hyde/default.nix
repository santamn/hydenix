# =============================================================================
# HyDE 本体を NixOS 向けにパッケージ化する
#
# HyDE はもともと Arch Linux 用の設定集なので、そのままでは動かない。
# buildPhase で主に次のものを潰してから $out にまるごとコピーしている。
#
#   1. プロセス名の違い   … NixOS はラッパー経由で起動するので実名が .waybar-wrapped になる
#   2. シンボリックリンク … home-manager がリンクで配置するため find がたどれない
#   3. バイナリの入手方法 … Arch は pacman やインストーラ前提。Nix パッケージ版に差し替える
#   4. Python と Lua の環境 … 実行時に uv や luarocks で作る環境は NixOS では誰も作らない
#   5. 未展開のアーカイブ … アイコン、GTK テーマ、GRUB テーマが .tar.gz のまま同梱されている
#   6. 上流の不具合       … Lua 化に追いついていない箇所や、このフォークで直したもの
#
# HyDE のファイルの書き換えは substituteInPlace --replace-fail か replaceInFiles で行う。
# HyDE を更新して置換元の文字列が消えたら、ビルドが失敗して気づける。
# 行番号を決め打ちする sed は使わない（AGENTS.md）。
#
# 詳細は docs-ja/03-hyde-package.md を参照。
# =============================================================================
{
  pkgs,
  lib,
  fetchFromGitHub,
  # interpreter for the Python scripts HyDE ships; override to add or drop libraries
  #
  # HyDE 同梱の Python スクリプトを動かすインタプリタ。
  # 上流は実行時に uv で venv ($XDG_STATE_HOME/hyde/python_env) を作る前提だが、
  # NixOS では誰もそれを作らないので、nixpkgs 側から渡す
  hydePython ?
    pkgs.python3.withPackages (
      ps:
        (with ps; [
          inotify-simple
          loguru
          pulsectl
          pygobject3
          pywayland
          requests
          xdg-base-dirs
        ])
        ++ [pkgs.pyamdgpuinfo]
    ),
  # Lua 5.5, the version Hyprland embeds, with the libraries HyDE's Lua scripts use.
  # HyDE installs them with luarocks into ~/.local/state/hyde/lua_env at runtime; Nix builds them here instead
  #
  # HyDE 同梱の Lua スクリプト（各種セレクタや open.lua など）を動かす環境。
  # lgi は GLib を typelib 経由で読むので、typelib・GSettings のスキーマ・dconf の GIO モジュールの場所を
  # ラッパーで環境変数に足している
  hydeLua ?
    pkgs.lua5_5.buildEnv.override {
      extraLibs = with pkgs.lua5_5.pkgs; [argparse dkjson lgi luafilesystem luasocket];
      makeWrapperArgs = [
        # lgi loads GLib and Gio from these typelibs (open.lua, batterynotify.lua, color/dconf.lua)
        "--prefix GI_TYPELIB_PATH : ${lib.makeSearchPath "lib/girepository-1.0" [pkgs.glib.out pkgs.gobject-introspection]}"
        # color/dconf.lua writes the GTK, icon and font settings to GSettings, which needs their schema and the dconf backend
        "--prefix XDG_DATA_DIRS : ${pkgs.glib.getSchemaDataDirPath pkgs.gsettings-desktop-schemas}"
        "--prefix GIO_EXTRA_MODULES : ${pkgs.dconf.lib}/lib/gio/modules"
      ];
    },
}: let
  src = fetchFromGitHub {
    owner = "HyDE-Project";
    repo = "HyDE";
    rev = "v26.08.21";
    hash = "sha256-+YhLk3J59zThsVVDsbTlSKcBulSxOO/r/HpPZ6Udg1M=";
  };
  version = lib.removePrefix "v" src.rev;
in
  pkgs.stdenv.mkDerivation {
    name = "hyde";
    inherit src version;

    # このフォークで直した waybar のツールチップ（CPU 温度の並び順、電力と電流の見出し、色分けなど）
    patches = [
      ./cpuinfo-tooltip.patch
      ./sensorsinfo-tooltip.patch
    ];

    nativeBuildInputs = with pkgs; [
      gnutar
    ];

    buildInputs = [hydeLua];

    buildPhase = ''
      runHook preBuild

      # remove assets folder
      rm -rf Source/assets

      # 同梱バイナリの削除。
      # hydectl / hyq は pkgs/ で個別にビルドしたものを使うため、
      # 同梱版を消して確実に Nix 版が使われるようにする。
      # hyde-ipc は上流で使われなくなったので、Nix 版も用意していない。
      # resetxdgportal.sh は modules/hm/hyde.nix が空スクリプトに差し替える
      rm -rf Configs/.local/lib/hyde/resetxdgportal.sh
      rm -rf Configs/.local/bin/hydectl
      rm -rf Configs/.local/bin/hyde-ipc
      rm -rf Configs/.local/lib/hyde/hyq
      rm -rf Configs/.local/bin/hyq

      # stdin で受け取ったファイルのうち、文字列を含むものすべてに substituteInPlace --replace-fail をかける。
      # どのファイルにも含まれていなければ失敗するので、HyDE の更新で置換元が消えたらビルドで気づける
      # substituteInPlace --replace-fail over the files on stdin that contain the string; fails when none does
      replaceInFiles() {
        local -a files
        mapfile -d "" files < <(xargs -0r grep -lIZF -- "$1")
        if [ ''${#files[@]} -eq 0 ]; then
          echo "no HyDE file contains '$1'" >&2
          return 1
        fi
        substituteInPlace "''${files[@]}" --replace-fail "$1" "$2"
      }

      # NixOS ではラッパースクリプト経由で起動されるため、実プロセス名が
      # 先頭ドット付きの `.waybar-wrapped` になる。
      # HyDE は `killall waybar` や `pgrep -x waybar` でバーを探すが該当プロセスが無く失敗するので、
      # 名前を置換して合わせる（waybar.py の "-x", "waybar" も同じ）。dunst / kitty / swaync も同様
      # Update waybar killall command in all HyDE files
      find . -type f -print0 | replaceInFiles 'killall waybar' 'killall .waybar-wrapped'
      find . -type f -print0 | replaceInFiles 'pgrep -x waybar' 'pgrep -x .waybar-wrapped'
      find . -type f -print0 | replaceInFiles '"-x", "waybar"' '"-x", ".waybar-wrapped"'

      # update dunst
      find . -type f -print0 | replaceInFiles 'killall dunst' 'killall .dunst-wrapped'

      # update kitty
      find . -type f -print0 | replaceInFiles 'killall -SIGUSR1 kitty' 'killall -SIGUSR1 .kitty-wrapped'

      # update swaync
      find . -type f -print0 | replaceInFiles 'pgrep -x swaync' 'pgrep -x .swaync-wrapped'

      #
      # 実行時 uv venv を指す参照を、すべて Nix のインタプリタへ向け直す。
      # hyde-shell (run_command) / gpuinfo.sh (AMD 分岐) / gamelauncher.sh は
      # "$XDG_STATE_HOME/hyde/python_env/bin/python" を直接 exec する。
      # そのパスは存在しないので、何も出力せずに終了して waybar のモジュールが空になっていた
      # point the runtime uv venv interpreter path at hydePython
      find . -type f -print0 | replaceInFiles ${lib.escapeShellArg "\${XDG_STATE_HOME:-$HOME/.local/state}/hyde/python_env/bin/python"} ${hydePython}/bin/python

      # hyde-shell は ~/.local/state/hyde/lua_env が無いと終了するので、hydeLua を指させる。
      # python_activate は先頭で return させて、uv の venv を有効化したり作ったりしないようにする
      # hyde-shell runs its Lua scripts against the luarocks tree HyDE builds at runtime; point it at hydeLua,
      # and stop it from activating or creating the uv venv that hydePython replaces
      substituteInPlace Configs/.local/bin/hyde-shell \
        --replace-fail 'l_env="''${XDG_STATE_HOME:-$HOME/.local/state}/hyde/lua_env"' 'l_env="${hydeLua}"' \
        --replace-fail 'python_activate() {' 'python_activate() { return 0'
      # `hyde-shell reload` が uv と luarocks で環境を作り直さないよう、python と lua の項目を消す
      # Nix provides both environments, so `hyde-shell reload` must not rebuild them with uv and luarocks
      substituteInPlace Configs/.local/lib/hyde/reload.py \
        --replace-fail '    "python": reload_python,' "" \
        --replace-fail '    "lua": reload_lua,' ""

      # HyDE のセレクタは同名のプリセットがあると最後に読んだディレクトリのものを残すので、
      # ~/.config/hypr の overrides が ~/.local/share/hypr の同名プリセットに負けていた。
      # 最初のディレクトリのものを残すように直す（ディレクトリ一覧の順序どおり）
      # let a preset under ~/.config/hypr replace HyDE's one of the same name; HyDE's selector keeps the last dir's copy instead
      substituteInPlace Configs/.local/lib/hyde/luautils/selector/common.lua \
        --replace-fail 'for _, entry in ipairs(files) do' 'for i, entry in ipairs(files) do' \
        --replace-fail 'local item = load_item(entry.path, entry.base)' 'local item = (i == 1 or files[i - 1].file ~= entry.file) and load_item(entry.path, entry.base)'

      # open.lua（SUPER+B/C/E）から起動したアプリに Lua 5.5 のモジュールパスを引き継がせると、
      # そのアプリから起動した LuaJIT のプログラムが Lua 5.5 用のモジュールを読み込んでしまうので、起動前に消す
      # the hydeLua wrapper and hyde-shell put Lua 5.5 module paths in LUA_PATH/LUA_CPATH; keep them from the apps open.lua launches
      substituteInPlace Configs/.local/lib/hyde/open.lua \
        --replace-fail 'local GLib = lgi.GLib' 'local GLib = lgi.GLib
      GLib.unsetenv("LUA_PATH")
      GLib.unsetenv("LUA_CPATH")'

      # grimblast は HyDE のインストーラがダウンロードするもので、リポジトリには無い。nixpkgs のものを使う
      # HyDE's installer downloads grimblast next to the scripts; the packaged one already speaks Hyprland's Lua IPC
      substituteInPlace Configs/.local/lib/hyde/screenshot.sh Configs/.local/lib/hyde/screenrecord.sh \
        --replace-fail '$LIB_DIR/hyde/screenshot/grimblast' '${lib.getExe pkgs.grimblast}'

      # Lua 設定の下では `hyprctl dispatch` も Lua で書く必要があり、
      # hypridle の dpms off/on と、waybar・hyde-shell のログアウト（exit 0）が失敗する。
      # HyDE の master にある修正を先取りしている
      # Hyprland's Lua config rejects dispatches in hyprlang syntax; backport HyDE's fixes from after v26.08.21
      substituteInPlace Configs/.config/hypr/hypridle.conf \
        --replace-fail 'hyprctl dispatch dpms off' "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'" \
        --replace-fail 'hyprctl dispatch dpms on' "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'"
      substituteInPlace Configs/.local/bin/hyde-shell Configs/.local/share/waybar/modules/custom-power{,menu}.jsonc \
        --replace-fail 'hyprctl dispatch exit 0' "hyprctl dispatch 'hl.dsp.exit()'"

      # v26.08.21 の Alt+Tab 切り替えは Alt の解放で確定する bind を使うが、non_consuming が無いため
      # Alt 単独の押下と解放を Hyprland が消費し、fcitx5 などの入力メソッドが Alt のホットキーを受け取れない
      # keep Hyprland from consuming the press and release of a lone Alt, so an input method sees it (e.g. fcitx5 hotkeys)
      substituteInPlace Configs/.local/share/hypr/lua/key_binds.lua \
        --replace-fail 'switch", release = true, transparent = true}' 'switch", release = true, transparent = true, non_consuming = true}'

      # swaync の style.css は最後の @import にセミコロンが無く、読み込むたびに GTK が警告を出す
      # Add a missing semicolon to the end of style.css for swaync
      substituteInPlace Configs/.config/swaync/style.css \
        --replace-fail $'@import "user-style.css"\n' $'@import "user-style.css";\n'

      # home-manager は設定ファイルを Nix ストアへのリンクとして配置する。
      # find は既定でリンクをたどらないため、HyDE のスクリプトがテーマや壁紙を
      # 見つけられなくなる。-L を付けてリンク先を追跡させる
      # fix find commands for symlinks
      find . -type f \( -executable -o -name "*.sh" \) -print0 | replaceInFiles 'find "' 'find -L "'

      # 以下は同梱アーカイブの展開。$out/share/ 以下に置くことで、
      # 各モジュールから "pkgs.hyde の share/..." として参照できるようになる。
      # フォントと VSCode 拡張は HyDE が 2026-07-27 のリリースで同梱をやめたので、ここでは扱わない。
      # フォントは modules/hm/hyde.nix が nixpkgs から、拡張は pkgs/code-wallbash.nix が入れる
      # BUILD GRUB THEMES
      mkdir -p $out/share/grub/themes
      tar xzf ./Source/arcs/Grub_Retroboot.tar.gz -C $out/share/grub/themes
      tar xzf ./Source/arcs/Grub_Pochita.tar.gz -C $out/share/grub/themes

      # BUILD ICONS
      mkdir -p $out/share/icons
      tar xzf ./Source/arcs/Icon_Wallbash.tar.gz -C $out/share/icons

      # BUILD GTK THEME
      mkdir -p $out/share/themes
      tar xzf ./Source/arcs/Gtk_Wallbash.tar.gz -C $out/share/themes

      runHook postBuild
    '';

    # 手直し済みのソースツリー「全体」を $out にコピーする。
    # これにより ${pkgs.hyde}/Configs/... という形で
    # HyDE の元のディレクトリ構造をそのまま参照できる
    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -r . $out

      runHook postInstall
    '';

    # inline the env instead of wrapProgram: hyde-shell is also sourced, and a wrapper's exec would kill the sourcing script
    # app2unit runs every `hyde-shell app` command, and HyDE's installer downloads it next to the scripts; hyde-shell runs the `which` command to find its own directory
    #
    # hyde-shell は実行されるだけでなく、HyDE のスクリプトから source される。
    # wrapProgram のラッパーは最後に exec するため、source した側のプロセスが
    # 置き換わってしまい、そのスクリプトは 1 行目で終了して何も出力しない。
    # そこで 2 行目に PATH の export を差し込む。
    # app2unit と which も PATH に入れる（app2unit は HyDE のインストーラがダウンロードするもので、リポジトリには無い）
    postInstall = ''
      hydeShell=$out/Configs/.local/bin/hyde-shell
      {
        head -n 1 "$hydeShell"
        echo 'export PATH="${pkgs.lib.makeBinPath [hydePython hydeLua pkgs.app2unit pkgs.which]}:$PATH"'
        tail -n +2 "$hydeShell"
      } >"$hydeShell.new"
      mv "$hydeShell.new" "$hydeShell"
      chmod +x "$hydeShell"
    '';

    # waybar.nix がビルド時に HyDE の waybar.py を実行するのに使う
    # for running HyDE's Python scripts at build time, as the waybar module does
    passthru = {inherit hydePython;};

    meta = {
      description = "HyDE, your Development Environment";
      homepage = "https://github.com/HyDE-Project/HyDE";
      license = lib.licenses.gpl3Only;
      maintainers = [];
      platforms = lib.platforms.all;
    };
  }
