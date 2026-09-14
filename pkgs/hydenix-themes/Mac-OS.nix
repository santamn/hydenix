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
    rev = "382a94b222aa41be1e018388240268c47aeb1dfa";
    inherit name;
    sha256 = "sha256-NQFmqjoOaANpGmS3FfuFqYjMONwwc9zLgvcMBXVDJxc=";
  };
  meta = {
    description = "HyDE Theme: Mac OS";
    homepage = "https://github.com/HyDE-Project/hyde-gallery/tree/Mac-Os";
  };
}
