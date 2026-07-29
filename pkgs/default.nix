# =============================================================================
# overlay の本体。ここで返した属性が pkgs に足され、
# 各モジュールから `pkgs.hyde` のように参照できるようになる。
#
#   final … すべての overlay 適用後の最終的な pkgs
#   prev  … 適用前の pkgs（ここでは使わないので _prev）
#
# callPackage は「定義ファイルの引数を pkgs から自動で埋める」仕組み。
# だから ./pokego/default.nix は {lib, buildGoModule, fetchFromGitHub} と
# 書くだけで済んでいる。
# =============================================================================
final: _prev: {
  # HyDE core packages
  hyde = final.callPackage ./hyde {}; # HyDE 本体（設定ファイル一式）
  hyde-config = final.callPackage ./hyde-config {}; # config.toml パーサ
  # 注意: sha256 が空のためビルドできない。誰も参照していないので表面化していない
  hyde-gallery = final.callPackage ./hyde-gallery {};
  hyde-ipc = final.callPackage ./hyde-ipc {}; # Hyprland のイベント購読・自動化
  hydectl = final.callPackage ./hydectl {}; # HyDE 操作 CLI
  hyprquery = final.callPackage ./hyprquery {}; # hyq: Hyprland 設定値の問い合わせ
  # Additional packages
  Bibata-Modern-Ice = final.callPackage ./Bibata-Modern-Ice.nix {};
  hydenix-themes = final.callPackage ./hydenix-themes {};
  pokego = final.callPackage ./pokego {};
  pyamdgpuinfo = final.callPackage ./pyamdgpuinfo {};
  Tela-circle-dracula = final.callPackage ./Tela-circle-dracula.nix {};
}
