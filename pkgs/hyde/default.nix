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
}: let
  src = fetchFromGitHub {
    owner = "HyDE-Project";
    repo = "HyDE";
    rev = "v26.7.4";
    hash = "sha256-saNXLFMSi2MFRR/RyPGV2KWCKCJqjWRIKGDqdv+f5VE=";
  };
  version = lib.removePrefix "v" src.rev;
in
  pkgs.stdenv.mkDerivation {
    name = "hyde";
    inherit src version;

    nativeBuildInputs = with pkgs; [
      gnutar
    ];

    buildPhase = ''
      runHook preBuild

      # remove assets folder
      rm -rf Source/assets

      rm -rf Configs/.local/lib/hyde/resetxdgportal.sh
      rm -rf Configs/.local/bin/hydectl
      rm -rf Configs/.local/bin/hyde-ipc
      rm -rf Configs/.local/lib/hyde/hyde-config
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
    postInstall = ''
      hydeShell=$out/Configs/.local/bin/hyde-shell
      {
        head -n 1 "$hydeShell"
        echo 'export PATH="${pkgs.lib.makeBinPath [hydePython]}:$PATH"'
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
