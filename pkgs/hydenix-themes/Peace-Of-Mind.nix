{
  pkgs,
  mkTheme,
}:
mkTheme rec {
  name = "Peace Of Mind";
  src = pkgs.fetchFromGitHub {
    owner = "Maroc02";
    repo = "Peace-Of-Mind";
    rev = "632fb4a0cba5af9d01b5b35899629565076ca295";
    inherit name;
    sha256 = "sha256-Vy0sk52PEo+5w9kOqr3VFVJQ59npHVQHa7hsbWqHvuE=";
  };
  meta = {
    inherit name;
    description = "HyDE Theme: Peace Of Mind";
    homepage = "https://github.com/Maroc02/Peace-Of-Mind";
  };
}
