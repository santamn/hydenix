{
  lib,
  runCommand,
}:
# Bundle the icons, GTK themes and fonts that the enabled themes ship.
# Like HyDE's theme.patch.sh, a directory several themes provide comes whole from the theme listed
# first, never mixed file by file with the copies of later themes. A later icon theme whose contents
# differ goes to alt/icons, which lands in a second XDG base directory where the spec merges the two.
themes: let
  merged =
    runCommand "hydenix-theme-assets" {
      meta = {
        description = "Icon, GTK theme and font assets of the selected HyDE themes";
        platforms = lib.platforms.all;
      };
    } ''
      shopt -s nullglob dotglob
      mkdir -p "$out"/{icons,themes,fonts} "$out/alt/icons"

      for theme in ${lib.escapeShellArgs themes}; do
        for kind in icons themes fonts; do
          for entry in "$theme/share/$kind"/*; do
            name=''${entry##*/}
            target="$out/$kind/$name"

            # no theme has taken this name yet, so link it as it is
            if [ ! -e "$target" ] && [ ! -L "$target" ]; then
              ln -s "$entry" "$target"
              continue
            fi

            # same contents, so one link is enough. --no-dereference leaves the arguments themselves
            # unresolved, so hand diff the directory the earlier link points at
            diff -rq --no-dereference "$(readlink "$target")" "$entry" >/dev/null 2>&1 && continue

            # GTK themes and fonts are not merged across base directories, so only the first copy
            # counts. A third icon copy has nowhere left to go either
            if [ "$kind" != icons ] || [ -e "$out/alt/icons/$name" ]; then
              echo "[skip] $kind/$name from $theme" >&2
              continue
            fi

            # keep the differing copy aside for the profile to merge back in
            ln -s "$entry" "$out/alt/icons/$name"
          done
        done
      done
    '';
in {
  # goes to ~/.local/share/{icons,themes,fonts}
  main = merged;

  # where the icon themes that lost the name above are kept
  altIcons =
    runCommand "hydenix-theme-alt-icons" {
      meta = {
        description = "Secondary copies of icon themes that more than one selected HyDE theme ships";
        platforms = lib.platforms.all;
      };
    } ''
      mkdir -p "$out/share"
      cp -a ${merged}/alt/icons "$out/share/icons"
    '';
}
