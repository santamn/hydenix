{pkgs}: let
  # Current pinned Hyde version
  hyde-pinned = pkgs.hyde;

  # Hyde at a commit on master. A fixed hash needs a fixed commit, so `rev` cannot be the branch name itself
  hyde-master = pkgs.hyde.overrideAttrs (old: {
    src = pkgs.fetchFromGitHub {
      owner = "HyDE-Project";
      repo = "HyDE";
      rev = "fa2fd57afc7203b1b5653d3271f3a57ea3873f97";
      sha256 = "sha256-/9oT3c60hZQtVdfbZWWUFo7GeU0pHQOWwhfsFELMoNE=";
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
