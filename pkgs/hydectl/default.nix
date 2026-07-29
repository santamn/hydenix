{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule {
  pname = "hydectl";
  version = "26.0.0";

  src = fetchFromGitHub {
    owner = "HyDE-Project";
    repo = "hydectl";
    rev = "v26.0.0";
    hash = "sha256-BHYaqXjClWiTrWrzXWKKT7HYWJrxvS9tFSKlm7Xdjjw=";
  };

  vendorHash = "sha256-6ItzWNTswxYYVBsg3SLVvwIQp1TAYeTOWXLjtKiPN3s=";
  proxyVendor = true;

  meta = with lib; {
    # 注意: mainProgram が "hyde-ipc" になっているが、正しくは "hydectl"。
    # `nix run .#hydectl` が別のバイナリを起動してしまう
    description = "Ported core scripts of HyDE";
    homepage = "https://github.com/HyDE-Project/hydectl";
    license = licenses.gpl3;
    maintainers = [];
    platforms = platforms.linux;
    mainProgram = "hyde-ipc";
  };
}
