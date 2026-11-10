{
  pkgs,
  lib,
  fetchFromGitHub,
  # interpreter for the Python scripts HyDE ships; override to add or drop libraries
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

      rm -rf Configs/.local/lib/hyde/resetxdgportal.sh
      rm -rf Configs/.local/bin/hydectl
      rm -rf Configs/.local/bin/hyde-ipc
      rm -rf Configs/.local/lib/hyde/hyq
      rm -rf Configs/.local/bin/hyq

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

      # nixpkgs' waybar runs as .waybar-wrapped; update the commands that match its exact process name
      find . -type f -print0 | replaceInFiles 'killall waybar' 'killall .waybar-wrapped'
      find . -type f -print0 | replaceInFiles 'pgrep -x waybar' 'pgrep -x .waybar-wrapped'
      find . -type f -print0 | replaceInFiles '"-x", "waybar"' '"-x", ".waybar-wrapped"'

      # update dunst
      find . -type f -print0 | replaceInFiles 'killall dunst' 'killall .dunst-wrapped'

      # update kitty
      find . -type f -print0 | replaceInFiles 'killall -SIGUSR1 kitty' 'killall -SIGUSR1 .kitty-wrapped'

      # update swaync
      find . -type f -print0 | replaceInFiles 'pgrep -x swaync' 'pgrep -x .swaync-wrapped'

      # point the runtime uv venv interpreter path at hydePython
      find . -type f -print0 | replaceInFiles ${lib.escapeShellArg "\${XDG_STATE_HOME:-$HOME/.local/state}/hyde/python_env/bin/python"} ${hydePython}/bin/python

      # hyde-shell runs its Lua scripts against the luarocks tree HyDE builds at runtime; point it at hydeLua,
      # and stop it from activating or creating the uv venv that hydePython replaces
      substituteInPlace Configs/.local/bin/hyde-shell \
        --replace-fail 'l_env="''${XDG_STATE_HOME:-$HOME/.local/state}/hyde/lua_env"' 'l_env="${hydeLua}"' \
        --replace-fail 'python_activate() {' 'python_activate() { return 0'
      # Nix provides both environments, so `hyde-shell reload` must not rebuild them with uv and luarocks
      substituteInPlace Configs/.local/lib/hyde/reload.py \
        --replace-fail '    "python": reload_python,' "" \
        --replace-fail '    "lua": reload_lua,' ""

      # let a preset under ~/.config/hypr replace HyDE's one of the same name; HyDE's selector keeps the last dir's copy instead
      substituteInPlace Configs/.local/lib/hyde/luautils/selector/common.lua \
        --replace-fail 'for _, entry in ipairs(files) do' 'for i, entry in ipairs(files) do' \
        --replace-fail 'local item = load_item(entry.path, entry.base)' 'local item = (i == 1 or files[i - 1].file ~= entry.file) and load_item(entry.path, entry.base)'

      # the hydeLua wrapper and hyde-shell put Lua 5.5 module paths in LUA_PATH/LUA_CPATH; keep them from the apps open.lua launches
      substituteInPlace Configs/.local/lib/hyde/open.lua \
        --replace-fail 'local GLib = lgi.GLib' 'local GLib = lgi.GLib
      GLib.unsetenv("LUA_PATH")
      GLib.unsetenv("LUA_CPATH")'

      # HyDE's installer downloads grimblast next to the scripts; the packaged one already speaks Hyprland's Lua IPC
      substituteInPlace Configs/.local/lib/hyde/screenshot.sh Configs/.local/lib/hyde/screenrecord.sh \
        --replace-fail '$LIB_DIR/hyde/screenshot/grimblast' '${lib.getExe pkgs.grimblast}'

      # Hyprland's Lua config rejects dispatches in hyprlang syntax; backport HyDE's fixes from after v26.08.21
      substituteInPlace Configs/.config/hypr/hypridle.conf \
        --replace-fail 'hyprctl dispatch dpms off' "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'" \
        --replace-fail 'hyprctl dispatch dpms on' "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'"
      substituteInPlace Configs/.local/bin/hyde-shell Configs/.local/share/waybar/modules/custom-power{,menu}.jsonc \
        --replace-fail 'hyprctl dispatch exit 0' "hyprctl dispatch 'hl.dsp.exit()'"

      # keep Hyprland from consuming the press and release of a lone Alt, so an input method sees it (e.g. fcitx5 hotkeys)
      substituteInPlace Configs/.local/share/hypr/lua/key_binds.lua \
        --replace-fail 'switch", release = true, transparent = true}' 'switch", release = true, transparent = true, non_consuming = true}'

      # Add a missing semicolon to the end of style.css for swaync
      substituteInPlace Configs/.config/swaync/style.css \
        --replace-fail $'@import "user-style.css"\n' $'@import "user-style.css";\n'

      # fix find commands for symlinks
      find . -type f \( -executable -o -name "*.sh" \) -print0 | replaceInFiles 'find "' 'find -L "'

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

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -r . $out

      runHook postInstall
    '';

    # inline the env instead of wrapProgram: hyde-shell is also sourced, and a wrapper's exec would kill the sourcing script
    # app2unit runs every `hyde-shell app` command, and HyDE's installer downloads it next to the scripts; hyde-shell runs the `which` command to find its own directory
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
