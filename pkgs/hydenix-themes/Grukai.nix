{
  pkgs,
  mkTheme,
}:
mkTheme rec {
  name = "Grukai";
  src = pkgs.fetchFromGitHub {
    owner = "amit-0i";
    repo = "Grukai";
    rev = "3945b4a154eeabf3cf916360ad182cb80eb2d51f";
    inherit name;
    sha256 = "sha256-5HOyo9uhQHhZZJFhpcwiY4ArWOdnL7yOkVAXhMva9LE=";
  };
  meta = {
    inherit name;
    description = "HyDE Theme: Grukai";
    homepage = "https://github.com/amit-0i/Grukai";
  };
}
