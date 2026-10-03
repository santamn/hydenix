{
  lib,
  cmake,
  pkg-config,
  spdlog,
  nlohmann_json,
  cli11,
  hyprlang,
  fetchFromGitHub,
}: let
  src = fetchFromGitHub {
    owner = "HyDE-Project";
    repo = "hyprquery";
    rev = "v0.6.7";
    hash = "sha256-2DtTKQUU3nlAnEzYQSP+ax43oWHi1sNNbp2epcSkzbs=";
  };
  version = lib.removePrefix "v" src.rev;
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
      spdlog
      nlohmann_json
      cli11
      hyprlang
    ];

    patches = [
      ./cmake-fix.patch
    ];

    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
      "-DUSE_SYSTEM_SPDLOG=ON"
      "-DUSE_SYSTEM_HYPRLANG=ON"
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
