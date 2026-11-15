{pkgs}: let
  # Current pinned Hyde version
  hyde-pinned = pkgs.hyde;

  # Hyde at a commit on master. A fixed hash needs a fixed commit, so `rev` cannot be the branch name itself
  hyde-master = pkgs.hyde.overrideAttrs (old: {
    src = pkgs.fetchFromGitHub {
      owner = "HyDE-Project";
      repo = "HyDE";
      rev = "cc824554ac63417d58253ea6764dc0045d963dce";
      sha256 = "sha256-WpsZmb4R9aePm958Xck50EOB0w36Xf7mFBbt+flB74o=";
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
