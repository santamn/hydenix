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
  # interpreter for the Lua scripts HyDE ships, in place of the luarocks tree upstream builds at runtime; Hyprland links Lua 5.5
  hydeLua ? let
    lua = pkgs.lua5_5;
    # nixpkgs marks lgi broken on Lua 5.4 and later; master builds on 5.5 and already carries nixpkgs' patches
    # shortcut: pinned to an untagged commit that Renovate cannot follow; move to a release once lgi tags one with Lua 5.5 support
    lgi = lua.pkgs.lgi.overrideAttrs (old: {
      version = "scm";
      src = fetchFromGitHub {
        owner = "lgi-devs";
        repo = "lgi";
        rev = "7a2276f9657a50ee548a636f2e646f96ec748bbd";
        hash = "sha256-YObCJg5RAW5TbZDo1e7NxdDqYaGbk8p5sbAzX7Y0lVg=";
      };
      knownRockspec = null;
      patches = [];
      meta = old.meta // {broken = false;};
    });
  in
    lua.buildEnv.override {
      extraLibs = with lua.pkgs; [argparse dkjson lgi luafilesystem luasocket];
      # open.lua and color/dconf.lua reach GLib through lgi and write the GNOME desktop settings through dconf
      makeWrapperArgs = [
        "--prefix GI_TYPELIB_PATH : ${lib.makeSearchPath "lib/girepository-1.0" [pkgs.glib.out pkgs.gobject-introspection]}"
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

      # Update waybar killall command in all HyDE files
      find . -type f -print0 | xargs -0 sed -i 's/killall waybar/killall .waybar-wrapped/g'

      # update dunst
      find . -type f -print0 | xargs -0 sed -i 's/killall dunst/killall .dunst-wrapped/g'

      # update kitty
      find . -type f -print0 | xargs -0 sed -i 's/killall kitty/killall .kitty-wrapped/g'
      find . -type f -print0 | xargs -0 sed -i 's/killall -SIGUSR1 kitty/killall -SIGUSR1 .kitty-wrapped/g'

      # update swaync
      find . -type f -print0 | xargs -0 sed -i 's/pgrep -x swaync/pgrep -x .swaync-wrapped/g'

      # point the runtime uv venv interpreter path at hydePython
      find . -type f -print0 | xargs -0 sed -i 's|''${XDG_STATE_HOME:-$HOME/\.local/state}/hyde/python_env/bin/python|${hydePython}/bin/python|g'

      # hyde-shell runs its Lua scripts against the luarocks tree upstream builds at runtime; point it at hydeLua,
      # and stop it from activating or creating the uv venv that hydePython replaces
      substituteInPlace Configs/.local/bin/hyde-shell \
        --replace-fail 'l_env="''${XDG_STATE_HOME:-$HOME/.local/state}/hyde/lua_env"' 'l_env="${hydeLua}"' \
        --replace-fail 'python_activate() {' 'python_activate() { return 0'
      # Nix provides both environments, so `hyde-shell reload` must not rebuild them with uv and luarocks
      substituteInPlace Configs/.local/lib/hyde/reload.py \
        --replace-fail '    "python": reload_python,' "" \
        --replace-fail '    "lua": reload_lua,' ""

      # the hydeLua wrapper and hyde-shell put Lua 5.5 module paths in LUA_PATH/LUA_CPATH; keep them from the apps open.lua launches
      substituteInPlace Configs/.local/lib/hyde/open.lua \
        --replace-fail 'local GLib = lgi.GLib' 'local GLib = lgi.GLib
      GLib.unsetenv("LUA_PATH")
      GLib.unsetenv("LUA_CPATH")'

      # upstream's installer downloads grimblast next to the scripts; the packaged one already speaks Hyprland's Lua IPC
      substituteInPlace Configs/.local/lib/hyde/screenshot.sh Configs/.local/lib/hyde/screenrecord.sh \
        --replace-fail '$LIB_DIR/hyde/screenshot/grimblast' '${lib.getExe pkgs.grimblast}'

      # Hyprland's Lua config rejects dispatches in hyprlang syntax; backport HyDE's fixes from after v26.08.21
      substituteInPlace Configs/.config/hypr/hypridle.conf \
        --replace-fail 'hyprctl dispatch dpms off' "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'" \
        --replace-fail 'hyprctl dispatch dpms on' "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'"
      substituteInPlace Configs/.local/bin/hyde-shell Configs/.local/share/waybar/modules/custom-power{,menu}.jsonc \
        --replace-fail 'hyprctl dispatch exit 0' "hyprctl dispatch 'hl.dsp.exit()'"

      # fix find commands for symlinks
      find . -type f -executable -print0 | xargs -0 sed -i 's/find "/find -L "/g'
      find . -type f -name "*.sh" -print0 | xargs -0 sed -i 's/find "/find -L "/g'

      # remove lines 187-190 from Configs/.local/lib/hyde/theme.switch.sh
      # fixes gtk4 themes
      # sed -i '187,190d' Configs/.local/lib/hyde/theme.switch.sh

      # remove pkill command from rofilaunch.sh
      # sed -i '2d' Configs/.local/lib/hyde/rofilaunch.sh

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
    # app2unit runs every `hyde-shell app` command, and upstream's installer downloads it next to the scripts; hyde-shell finds itself with which
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

    meta = {
      description = "HyDE, your Development Environment";
      homepage = "https://github.com/HyDE-Project/HyDE";
      license = lib.licenses.gpl3Only;
      maintainers = [];
      platforms = lib.platforms.all;
    };
  }
