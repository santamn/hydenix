{
  pkgs,
  mkTheme,
}:
mkTheme rec {
  name = "Electra";
  src = pkgs.fetchFromGitHub {
    owner = "XBEAST1";
    repo = "Electra";
    rev = "953676ce3962b0ce2bf8bf06c67584f325183e4a";
    inherit name;
    sha256 = "sha256-BpgfGdr0g2ufR+Itl0UIBjftkzt5wQx1CMca60ZyEKk=";
  };
  meta = {
    inherit name;
    description = "HyDE Theme: Electra";
    homepage = "https://github.com/XBEAST1/Electra";
  };
}
