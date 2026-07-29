# HyDE 更新の差分確認ツール。
# 固定中の HyDE と upstream の master を比較し、.hyde-cache/ に差分を出す。
#
#   nix run .#hyde-diff-upstream   … 上流 master との差分
#   nix run .#hyde-diff-home       … 自分のホーム構成との差分
#
# 注意: master を rev に指定しつつ sha256 を固定しているため、
# 上流が進むとハッシュ不一致でビルドが失敗する。使うときは sha256 の更新が要る。
{pkgs}: let
  # Current pinned Hyde version
  hyde-pinned = pkgs.hyde;

  # Latest master Hyde version
  hyde-master = pkgs.hyde.overrideAttrs (_old: {
    src = pkgs.fetchFromGitHub {
      owner = "HyDE-Project";
      repo = "HyDE";
      rev = "master";
      sha256 = "sha256-cNOryXKFpVSTiAuzD0VQAV+2GQhJTTs1HBM6Z0cZoFo=";
    };
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
  }
