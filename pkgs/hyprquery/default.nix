{
  lib,
  stdenv,
  cmake,
  pkg-config,
  spdlog,
  nlohmann_json,
  cli11,
  hyprlang,
  autoPatchelfHook,
  fetchFromGitHub,
}: let
  # renovate rewrites `rev` and nothing else; `version` is derived from it
  src = fetchFromGitHub {
    owner = "HyDE-Project";
    repo = "hyprquery";
    rev = "v0.6.7";
    hash = "sha256-2DtTKQUU3nlAnEzYQSP+ax43oWHi1sNNbp2epcSkzbs=";
  };
  version = lib.removePrefix "v" src.rev;
in
  stdenv.mkDerivation {
    pname = "hyprquery";
    inherit src version;

    nativeBuildInputs = [
      cmake
      pkg-config
      autoPatchelfHook
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

    meta = with lib; {
      description = "A command-line utility for querying configuration values from Hyprland";
      homepage = "https://github.com/HyDE-Project/hyprquery";
      license = licenses.mit;
      maintainers = [];
      platforms = platforms.linux;
      mainProgram = "hyq";
    };
  }
