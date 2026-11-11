{
  pkgs,
  mkTheme,
}:
mkTheme rec {
  name = "1-Bit";
  src = pkgs.fetchFromGitHub {
    owner = "amit-0i";
    repo = "1-Bit";
    # locking commit
    rev = "84b2f94e8a340d324deaf293449e5508553eb128";
    inherit name;
    sha256 = "sha256-hhSi7R2MHlcLIMou7Mq91r2iVRkWG7t4ODt6jDzAV/Y=";
  };
  meta = {
    inherit name;
    description = "HyDE Theme: 1-Bit";
    homepage = "https://github.com/amit-0i/1-Bit";
  };
}
