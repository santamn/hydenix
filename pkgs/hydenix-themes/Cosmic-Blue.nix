{
  pkgs,
  mkTheme,
}:
mkTheme rec {
  name = "Cosmic Blue";
  src = pkgs.fetchFromGitHub {
    owner = "Maroc02";
    repo = "Cosmic-Blue";
    rev = "ad8a9a50684f9ab6dbd29cd98b6c2a3f457347f3";
    inherit name;
    sha256 = "sha256-4o/w7QViz8sD+dpzd9KWcoXUC+H7tn57JlzlRoPp9q8=";
  };
  meta = {
    description = "HyDE Theme: Cosmic Blue";
    homepage = "https://github.com/Maroc02/Cosmic-Blue";
  };
}
