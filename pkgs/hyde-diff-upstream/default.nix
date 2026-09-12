{pkgs}: let
  # Current pinned Hyde version
  hyde-pinned = pkgs.hyde;

  # Hyde at a commit on master. A fixed hash needs a fixed commit, so `rev` cannot be the branch name itself
  hyde-master = pkgs.hyde.overrideAttrs (old: {
    src = pkgs.fetchFromGitHub {
      owner = "HyDE-Project";
      repo = "HyDE";
      rev = "5e831ab5ee393a30e9889b4964a591c5cb015eeb";
      sha256 = "sha256-0ApoQrMQLXKWFz2Y+h8MZmjW1xSQ7sKObqB8HJ2n2o8=";
    };
    passthru = (old.passthru or {}) // {updateBranch = "master";};
  });
in
  pkgs.writeShellApplication {
    name = "hyde-diff-upstream";
    runtimeInputs = with pkgs; [
      coreutils
      diffutils
    ];
    # Pass the built packages to the script
    text = ''
      export HYDE_PINNED="${hyde-pinned}"
      export HYDE_MASTER="${hyde-master}"
      ${builtins.readFile ./run.sh}
    '';
    # `nix run .#update-branch-pins` reaches the master build through this
    passthru = {inherit hyde-master;};
  }
