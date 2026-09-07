{
  rustPlatform,
  fetchFromGitHub,
  lib,
  pkgs,
}: let
  # renovate rewrites `rev` and nothing else; `version` is derived from it
  src = fetchFromGitHub {
    owner = "HyDE-Project";
    repo = "hyde-ipc";
    rev = "v0.1.6";
    hash = "sha256-vGjxEd2P2rQ1iKZQTmdqZ8WijxO+zT8cecQulu6beB8=";
  };
  version = lib.removePrefix "v" src.rev;
in
  rustPlatform.buildRustPackage {
    pname = "hyde-ipc";
    inherit src version;

    cargoHash = "sha256-abWXwpsh2QB7McBmTxAg3B6ayrEtkum183UznLoCMxU=";

    # Build the 'cli' package within the workspace
    cargoBuildFlags = [
      "--package"
      "hyde-ipc"
    ];

    # Install the resulting binary
    installTargets = ["hyde-ipc"];

    buildInputs = [
      pkgs.pkg-config
      pkgs.openssl
      pkgs.libiconv
    ];

    meta = with lib; {
      description = "Control Hyprland, query its state, listen for events, and create automated reactions to events";
      homepage = "https://github.com/HyDE-Project/hyde-ipc";
      license = licenses.mit;
      maintainers = [];
      platforms = platforms.linux;
      mainProgram = "hyde-ipc";
    };
  }
