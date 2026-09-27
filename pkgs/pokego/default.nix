{
  lib,
  buildGoLatestModule,
  fetchFromGitHub,
}: let
  src = fetchFromGitHub {
    owner = "rubiin";
    repo = "pokego";
    rev = "v0.6.0";
    hash = "sha256-0zlOyEsgdFmWzQg8/O9VYkM5kZM3c63DHH9rqhLhG70=";
  };
  version = lib.removePrefix "v" src.rev;
in
  buildGoLatestModule {
    pname = "pokego";
    inherit src version;

    vendorHash = "sha256-7K17JaXFsjf163g5PXCb5ng2gYdotnZ2IDKk8KFjNj0=";

    # Install shell completions
    postInstall = ''
      install -Dm644 completions/pokego.bash "$out/share/bash-completion/completions/pokego"
      install -Dm644 completions/pokego.fish "$out/share/fish/vendor_completions.d/pokego.fish"
      install -Dm644 completions/pokego.zsh "$out/share/zsh/site-functions/_pokego"
    '';

    meta = {
      description = "Command-line tool that lets you display Pokémon sprites in color directly in your terminal";
      homepage = "https://github.com/rubiin/pokego";
      license = lib.licenses.gpl3Only;
      mainProgram = "pokego";
      platforms = lib.platforms.all;
    };
  }
