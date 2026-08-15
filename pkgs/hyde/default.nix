{
  pkgs,
  lib,
  fetchFromGitHub,
  # Interpreter for the Python scripts HyDE ships. Upstream builds a uv venv at
  # runtime ($XDG_STATE_HOME/hyde/python_env); on NixOS nothing ever creates it,
  # so the interpreter is provided from nixpkgs instead. Override this argument
  # to add or drop libraries.
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
}:
pkgs.stdenv.mkDerivation {
  name = "hyde";
  version = "26.7.4";

  src = fetchFromGitHub {
    owner = "HyDE-Project";
    repo = "HyDE";
    rev = "v26.7.4";
    hash = "sha256-saNXLFMSi2MFRR/RyPGV2KWCKCJqjWRIKGDqdv+f5VE=";
  };

  nativeBuildInputs = with pkgs; [
    gnutar
    unzip
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

    # Point every call to the runtime uv venv at the Nix interpreter.
    # hyde-shell (run_command), gpuinfo.sh (AMD branch) and gamelauncher.sh all
    # exec "$XDG_STATE_HOME/hyde/python_env/bin/python" directly; that path does
    # not exist here, so those commands died before printing anything and their
    # waybar modules stayed empty.
    find . -type f -print0 | xargs -0 sed -i 's|''${XDG_STATE_HOME:-$HOME/\.local/state}/hyde/python_env/bin/python|${hydePython}/bin/python|g'

    # fix find commands for symlinks
    find . -type f -executable -print0 | xargs -0 sed -i 's/find "/find -L "/g'
    find . -type f -name "*.sh" -print0 | xargs -0 sed -i 's/find "/find -L "/g'

    # remove lines 187-190 from Configs/.local/lib/hyde/theme.switch.sh
    # fixes gtk4 themes
    # sed -i '187,190d' Configs/.local/lib/hyde/theme.switch.sh

    # remove pkill command from rofilaunch.sh
    # sed -i '2d' Configs/.local/lib/hyde/rofilaunch.sh

    # BUILD FONTS
    mkdir -p $out/share/fonts/truetype
    for fontarchive in ./Source/arcs/Font_*.tar.gz; do
      if [ -f "$fontarchive" ]; then
        tar xzf "$fontarchive" -C $out/share/fonts/truetype/
      fi
    done

    # BUILD VSCODE EXTENSION
    mkdir -p $out/share/vscode/extensions/prasanthrangan.wallbash
    unzip ./Source/arcs/Code_Wallbash.vsix -d $out/share/vscode/extensions/prasanthrangan.wallbash
    # Ensure extension is readable and executable
    chmod -R a+rX $out/share/vscode/extensions/prasanthrangan.wallbash

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

  # hyde-shell is not only executed, it is also sourced by HyDE scripts:
  # hyprsunset.sh, hyprlock.sh, animations.sh, workflows.sh and
  # wallpaper.mpvpaper.sh all start with `source "$(which hyde-shell)"`.
  # A wrapProgram wrapper ends in `exec`, which replaces the sourcing script's
  # process, so those scripts die at their first line and produce no output.
  # Inline the environment into the script itself instead of wrapping it, so
  # hyde-shell stays safe to source.
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
