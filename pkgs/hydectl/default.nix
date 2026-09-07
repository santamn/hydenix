{
  lib,
  buildGoModule,
  fetchFromGitHub,
}: let
  # renovate rewrites `rev` and nothing else; `version` is derived from it
  src = fetchFromGitHub {
    owner = "HyDE-Project";
    repo = "hydectl";
    rev = "v26.0.0";
    hash = "sha256-BHYaqXjClWiTrWrzXWKKT7HYWJrxvS9tFSKlm7Xdjjw=";
  };
  version = lib.removePrefix "v" src.rev;
in
  buildGoModule {
    pname = "hydectl";
    inherit src version;

    vendorHash = "sha256-6ItzWNTswxYYVBsg3SLVvwIQp1TAYeTOWXLjtKiPN3s=";
    proxyVendor = true;

    meta = with lib; {
      description = "Ported core scripts of HyDE";
      homepage = "https://github.com/HyDE-Project/hydectl";
      license = licenses.gpl3;
      maintainers = [];
      platforms = platforms.linux;
      mainProgram = "hydectl";
    };
  }
