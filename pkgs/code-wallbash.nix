{
  lib,
  fetchFromGitHub,
  unzip,
  vscode-utils,
}: let
  src = fetchFromGitHub {
    owner = "HyDE-Project";
    repo = "code-wallbash";
    rev = "v0.3.7";
    hash = "sha256-hmwq5ex0Bv4i3rfFTj44gmAckC4fz//BtDQzmj7vGTM=";
  };
  version = lib.removePrefix "v" src.rev;
in
  vscode-utils.buildVscodeExtension {
    pname = "code-wallbash";
    inherit src version;

    # the vsix is committed to the repository; unpacking it here keeps `src` a
    # fetcher, which is what nix-update needs to rewrite the hash
    nativeBuildInputs = [unzip];
    unpackCmd = ''unzip -qq "$curSrc/release/Code_Wallbash.vsix"'';

    vscodeExtPublisher = "thehydeproject";
    vscodeExtName = "wallbash";
    vscodeExtUniqueId = "thehydeproject.wallbash";

    meta = {
      description = "VSCode extension that themes the editor with wallbash colors";
      homepage = "https://github.com/HyDE-Project/code-wallbash";
      license = lib.licenses.gpl3Only;
      maintainers = [];
      platforms = lib.platforms.all;
    };
  }
