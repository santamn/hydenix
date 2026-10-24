{
  lib,
  cmake,
  pkg-config,
  libxkbcommon,
  nlohmann_json,
  cli11,
  hyprlang,
  fetchFromGitHub,
}: let
  # shortcut: `--dump` and `--export lua`, which HyDE's theme switch needs, exist only on main; pin a release once one has them
  src = fetchFromGitHub {
    owner = "HyDE-Project";
    repo = "hyprquery";
    rev = "002af783eeb8c487a4bf90d75e5a804340557967";
    hash = "sha256-nGvpj4vbhUX2Xh6usUPQghKdj2Wy6ADMU16SSrKwzkA=";
  };
  version = "0.6.8-unstable-2026-06-13";
in
  # nixpkgs builds hyprlang with a newer GCC than the default stdenv, and linking it against an older libstdc++ fails
  hyprlang.stdenv.mkDerivation {
    pname = "hyprquery";
    inherit src version;

    nativeBuildInputs = [
      cmake
      pkg-config
    ];

    buildInputs = [
      libxkbcommon
      nlohmann_json
      cli11
      hyprlang
    ];

    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
      "-DHYPRQUERY_DISTRO_BUILD=ON"
    ];

    # A wrong libstdc++ in the RUNPATH still links, but fails as soon as the binary is loaded
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      $out/bin/hyq --help >/dev/null
      runHook postInstallCheck
    '';

    meta = with lib; {
      description = "A command-line utility for querying configuration values from Hyprland";
      homepage = "https://github.com/HyDE-Project/hyprquery";
      license = licenses.mit;
      maintainers = [];
      platforms = platforms.linux;
      mainProgram = "hyq";
    };
  }
