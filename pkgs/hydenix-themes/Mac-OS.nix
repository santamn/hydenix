{
  pkgs,
  mkTheme,
}:
mkTheme rec {
  name = "Mac OS";
  branch = "Mac-Os";
  src = pkgs.fetchFromGitHub {
    owner = "HyDE-Project";
    repo = "hyde-gallery";
    rev = "f276fd5914a8e45e356a21ad8a7f705710b13f26";
    inherit name;
    sha256 = "sha256-larDxuslmWA3fOGIQc4VNWq/nlIqRGkfnyKp057O90g=";
  };
  meta = {
    description = "HyDE Theme: Mac OS";
    homepage = "https://github.com/HyDE-Project/hyde-gallery/tree/Mac-Os";
  };
}
