{
  lib,
  stdenv,
  pkgs,
}:
stdenv.mkDerivation {
  pname = "Tela-dracula-icon-theme";
  version = "1.0.0"; # You may want to update this with a specific version

  # Pinned to a commit instead of refs/heads/Catppuccin-Mocha. A branch ref is mutable,
  # so the upstream repo can move or delete the file out from under this fixed-output
  # hash at any time -- which is exactly how Bibata-Modern-Ice.nix broke. Same archive
  # bytes as the branch head at the time of pinning, so the hash is unchanged.
  src = pkgs.fetchurl {
    url = "https://github.com/HyDE-Project/hyde-themes/raw/415d22a6bb6348a6d09c11307be54c592fb15138/Source/Icon_TelaDracula.tar.gz";
    sha256 = "sha256-UgYCOJrtzwLkIuG7v/CJ33dwHXQdFhbdCRuTzp4LUms=";
  };

  nativeBuildInputs = with pkgs; [
    jdupes
  ];

  installPhase = ''
    mkdir -p $out/share/icons
    tar -xf $src -C $out/share/icons
    jdupes --recurse $out/share/icons
  '';

  meta = {
    description = "Tela Dracula icon theme from HyDE Project";
    homepage = "https://github.com/HyDE-Project/hyde-themes";
    license = lib.licenses.gpl3; # You may need to verify the actual license
    maintainers = [];
    platforms = lib.platforms.all;
  };
}
