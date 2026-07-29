{
  lib,
  stdenv,
  pkgs,
}:
stdenv.mkDerivation {
  pname = "Bibata-Modern-Ice";
  version = "1.0.0";

  # Pinned to a commit instead of refs/heads/master. HyDE deleted this archive from
  # Source/arcs/ in b8cc647 ("Release - rc -> master", 2026-07-27), so the branch URL
  # now 404s and this package stopped building. a51460a is that commit's parent -- the
  # last revision still carrying the archive -- and is tagged v26.7.4, the release
  # pkgs/hyde pins, which keeps the cursor in sync with the packaged HyDE.
  src = pkgs.fetchurl {
    url = "https://github.com/HyDE-Project/HyDE/raw/a51460a7b1a822ee7194318b60a38850f711b923/Source/arcs/Cursor_BibataIce.tar.gz";
    sha256 = "sha256-pYvIxOZ3jvcLrv4bDYPc0FPkPLydyWwltFLCZ7aILaQ=";
  };

  nativeBuildInputs = with pkgs; [
    jdupes
  ];

  installPhase = ''
    mkdir -p $out/share/icons/
    tar -xf $src -C $out/share/icons/
    jdupes --recurse $out/share/icons/
  '';

  meta = {
    description = "Bibata Modern Ice cursor theme";
    homepage = "https://github.com/HyDE-Project/HyDE";
    license = lib.licenses.gpl3;
    maintainers = [];
    platforms = lib.platforms.all;
  };
}
