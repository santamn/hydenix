{
  pkgs,
  mkTheme,
}:
mkTheme rec {
  name = "Obsidian-Purple";
  src = pkgs.fetchFromGitHub {
    owner = "amit-0i";
    repo = "Obsidian-Purple";
    rev = "b73f00b1202f9891473572f038fa52efaa622951";
    inherit name;
    sha256 = "sha256-kNpAcelCY06MdbFUQHxJxwfCpZh1E65Y+9T27gJSWfg=";
  };
  meta = {
    inherit name;
    description = "HyDE Theme: Obsidian-Purple";
    homepage = "https://github.com/amit-0i/Obsidian-Purple";
  };
}
