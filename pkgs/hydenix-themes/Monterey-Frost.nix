{
  pkgs,
  mkTheme,
}:
mkTheme rec {
  name = "Monterey Frost";
  src = pkgs.fetchFromGitHub {
    owner = "rishav12s";
    repo = "Monterey-Frost";
    rev = "559edd928d63183c8269052f4739b3d07dca9091";
    inherit name;
    sha256 = "sha256-RpCLKIssAqz6wcbIA8Fzz0feenL3UTEUXGvPGlbLm0o=";
  };
  meta = {
    description = "Mac-OS inspired dark theme";
    homepage = "https://github.com/rishav12s/Monterey-Frost";
  };
}
