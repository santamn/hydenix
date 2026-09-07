{
  lib,
  fetchFromGitHub,
  vscode-utils,
}: let
  src = fetchFromGitHub {
    owner = "HyDE-Project";
    repo = "code-wallbash";
    rev = "v0.3.7";
    hash = "sha256-hmwq5ex0Bv4i3rfFTj44gmAckC4fz//BtDQzmj7vGTM=";
  };
in
  vscode-utils.buildVscodeExtension {
    pname = "code-wallbash";
    version = "0.3.7";

    src = "${src}/release/Code_Wallbash.vsix";

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
