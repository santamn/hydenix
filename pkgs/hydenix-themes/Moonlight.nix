{
  pkgs,
  mkTheme,
}:
mkTheme rec {
  name = "Moonlight";
  src = pkgs.fetchFromGitHub {
    owner = "Maroc02";
    repo = "Moonlight";
    rev = "50f77a6e9b6bbf6d96aec5ec4b5c7ae4d7605ece";
    inherit name;
    sha256 = "sha256-mFTmAIEsRBo958z1Dyt2uH8+VIpyZzGQ3Pgzkmqaq7I=";
  };
  meta = {
    description = "HyDE Theme: Moonlight";
    homepage = "https://github.com/Maroc02/Moonlight";
  };
}
