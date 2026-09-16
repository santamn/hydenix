# This module extends home.file, xdg.configFile and xdg.dataFile with the `mutable` option.
{
  config,
  lib,
  pkgs,
  ...
}: let
  mutableOption = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options.mutable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to copy the file without the read-only attribute instead of
          symlinking. If you set this to `true`, you must also set `force` to
          `true`. A mutable file is deleted once it is gone from your
          configuration, including any change you made to it after it was
          copied.

          This option is useful for programs that don't have a very good
          support for read-only configurations.
        '';
      };
    });
  };

  # Home Manager merges xdg.configFile and xdg.dataFile into home.file.
  mutableFiles = lib.filter (file: file.enable && file.mutable) (lib.attrValues config.home.file);
in {
  options = {
    home.file = mutableOption;
    xdg.configFile = mutableOption;
    xdg.dataFile = mutableOption;
  };

  config = {
    assertions =
      map (file: {
        assertion = file.force;
        message = "${file.target}: `mutable = true` requires `force = true`";
      })
      mutableFiles;

    # The targets this generation copies, read by its own activation and by the next one.
    home.extraBuilderCommands = let
      manifest = pkgs.writeText "mutable-files" (lib.concatLines (map (file: file.target) mutableFiles));
    in "ln -s ${manifest} $out/mutable-files";

    # Turns copies the new generation no longer makes back into links of the old generation,
    # so that linkGeneration deletes or relinks them like any other.
    home.activation.mutableFileCleanup = lib.hm.dag.entryBetween ["linkGeneration"] ["writeBoundary" "checkFilesChanged"] ''
      function relinkStaleMutableCopies() {
        if [[ ! -v oldGenPath || ! -e $oldGenPath/mutable-files ]]; then
          return
        fi

        local newGenFiles oldGenFiles
        newGenFiles="$(readlink -e "$newGenPath/home-files")"
        oldGenFiles="$(readlink -e "$oldGenPath/home-files")"

        local -A stillMutable=()
        local target
        while IFS= read -r target; do
          stillMutable[$target]=1
        done < "$newGenPath/mutable-files"

        local oldSource path
        while IFS= read -r target; do
          # Walk the old tree so that files the user added next to a recursive target's copies stay untouched.
          while IFS= read -r -d "" oldSource; do
            path="''${oldSource#"$oldGenFiles"/}"

            # Gone already, or still a link.
            if [[ ! -f $HOME/$path || -L $HOME/$path ]]; then
              continue
            fi

            if [[ -e $newGenFiles/$path ]]; then
              # Still mutable, so the copy step overwrites it.
              if [[ -n ''${stillMutable[$target]-} ]]; then
                continue
              fi
              # Now a link. An edited copy goes through Home Manager's collision handling instead.
              if ! cmp -s "$newGenFiles/$path" "$HOME/$path"; then
                continue
              fi
            fi

            run ln -sf $VERBOSE_ARG "$oldSource" "$HOME/$path"
          done < <(find "$oldGenFiles/$target" \( -type f -o -type l \) -print0)
        done < "$oldGenPath/mutable-files"
      }

      relinkStaleMutableCopies
    '';

    home.activation.mutableFileGeneration = lib.hm.dag.entryAfter ["linkGeneration"] ''
      function copyMutableFiles() {
        echo "Copying mutable home files for $HOME"

        local target
        while IFS= read -r target; do
          # -T merges a recursive target into the directory linkGeneration made.
          run cp -rLT --remove-destination "$newGenPath/home-files/$target" "$HOME/$target"
          # The store's modes are read-only.
          run chmod -R u+w "$HOME/$target"
        done < "$newGenPath/mutable-files"
      }

      copyMutableFiles
    '';
  };
}
