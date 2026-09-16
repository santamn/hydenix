{
  lib,
  buildGoLatestModule,
  fetchFromGitHub,
}: let
  src = fetchFromGitHub {
    owner = "rubiin";
    repo = "pokego";
    rev = "v0.5.8";
    hash = "sha256-pZGxE58Jfi7oRkYph36XEFXBsxctJ3wAD8YvjEp6l18=";
  };
  version = lib.removePrefix "v" src.rev;
in
  buildGoLatestModule {
    pname = "pokego";
    inherit src version;

    vendorHash = "sha256-Ip2GuQDOolMyDvfmXcJRlY2rMp1amS8owkqcNMOR1+Y=";

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
