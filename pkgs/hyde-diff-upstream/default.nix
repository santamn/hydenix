# HyDE 更新の差分確認ツール。
# 固定中の HyDE と upstream の master を比較し、.hyde-cache/ に差分を出す。
#
#   nix run .#hyde-diff-upstream   … 上流 master との差分
#   nix run .#hyde-diff-home       … 自分のホーム構成との差分
#
# master 側は commit で固定している。ブランチ名を rev に書くと、上流が進んだ時点で
# sha256 が合わなくなりビルドが失敗していた。
# この commit は update-branch-pins.yml が毎晩 master の先頭へ進める（passthru.updateBranch）。
# 書き換わるのはこのファイルで、pkgs/hyde の rev には触らない
{pkgs}: let
  # Current pinned Hyde version
  hyde-pinned = pkgs.hyde;

  # Hyde at a commit on master. A fixed hash needs a fixed commit, so `rev` cannot be the branch name itself
  hyde-master = pkgs.hyde.overrideAttrs (old: {
    src = pkgs.fetchFromGitHub {
      owner = "HyDE-Project";
      repo = "HyDE";
      rev = "7c7b832d479620133fb0a2bdec0fe20cf2e7c90a";
      sha256 = "sha256-+YhLk3J59zThsVVDsbTlSKcBulSxOO/r/HpPZ6Udg1M=";
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
