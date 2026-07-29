# =============================================================================
# HyDE 本体を NixOS 向けにパッケージ化する
#
# HyDE はもともと Arch Linux 用の設定集なので、そのままでは動かない。
# buildPhase で次の 4 つを潰してから $out にまるごとコピーしている。
#
#   1. プロセス名の違い   … NixOS はラッパー経由で起動するので実名が .waybar-wrapped になる
#   2. シンボリックリンク … home-manager がリンクで配置するため find がたどれない
#   3. バイナリの入手方法 … Arch は pacman 前提。Nix パッケージ版に差し替える
#   4. 未展開のアーカイブ … フォント・アイコン・GRUB テーマが .tar.gz のまま同梱されている
#
# 詳細は docs-ja/03-hyde-package.md を参照。
# =============================================================================
{
  pkgs,
  lib,
  fetchFromGitHub,
}:
pkgs.stdenv.mkDerivation {
  name = "hyde";
  version = "0-unstable-2026-05-26";

  src = fetchFromGitHub {
    owner = "HyDE-Project";
    repo = "HyDE";
    rev = "a51460a7b1a822ee7194318b60a38850f711b923";
    hash = "sha256-saNXLFMSi2MFRR/RyPGV2KWCKCJqjWRIKGDqdv+f5VE=";
  };

  nativeBuildInputs = with pkgs; [
    gnutar
    unzip
    makeWrapper
  ];

  buildPhase = ''
    runHook preBuild

    # remove assets folder
    # 素材フォルダ。実行時に不要かつ容量が大きい
    rm -rf Source/assets

    # 同梱バイナリの削除。
    # hydectl / hyq / hyde-ipc / hyde-config は pkgs/ で個別にビルドしたものを使うため、
    # 同梱版を消して確実に Nix 版が使われるようにする。
    # resetxdgportal.sh は modules/hm/hyde.nix が空スクリプトに差し替える
    rm -rf Configs/.local/lib/hyde/resetxdgportal.sh
    rm -rf Configs/.local/bin/hydectl
    rm -rf Configs/.local/bin/hyde-ipc
    rm -rf Configs/.local/lib/hyde/hyde-config
    rm -rf Configs/.local/lib/hyde/hyq
    rm -rf Configs/.local/bin/hyq

    # Update waybar killall command in all HyDE files
    # NixOS ではラッパースクリプト経由で起動されるため、実プロセス名が
    # 先頭ドット付きの `.waybar-wrapped` になる。
    # HyDE は `killall waybar` でバーを再起動しようとするが該当プロセスが無く失敗するので、
    # 名前を置換して合わせる（waybar / dunst / kitty の 3 つが対象）
    find . -type f -print0 | xargs -0 sed -i 's/killall waybar/killall .waybar-wrapped/g'

    # update dunst
    find . -type f -print0 | xargs -0 sed -i 's/killall dunst/killall .dunst-wrapped/g'

    # update kitty
    find . -type f -print0 | xargs -0 sed -i 's/killall kitty/killall .kitty-wrapped/g'
    find . -type f -print0 | xargs -0 sed -i 's/killall -SIGUSR1 kitty/killall -SIGUSR1 .kitty-wrapped/g'

    # fix find commands for symlinks
    # home-manager は設定ファイルを Nix ストアへのリンクとして配置する。
    # find は既定でリンクをたどらないため、HyDE のスクリプトがテーマや壁紙を
    # 見つけられなくなる。-L を付けてリンク先を追跡させる
    find . -type f -executable -print0 | xargs -0 sed -i 's/find "/find -L "/g'
    find . -type f -name "*.sh" -print0 | xargs -0 sed -i 's/find "/find -L "/g'

    # remove lines 187-190 from Configs/.local/lib/hyde/theme.switch.sh
    # fixes gtk4 themes
    # 行番号の決め打ちは HyDE 更新時に誤爆するため、フォークでは無効化されている。
    # 復活させるときは必ず `nix run .#hyde-diff-upstream` で差分を確認すること
    # sed -i '187,190d' Configs/.local/lib/hyde/theme.switch.sh

    # remove pkill command from rofilaunch.sh
    # sed -i '2d' Configs/.local/lib/hyde/rofilaunch.sh

    # 以下は同梱アーカイブの展開。$out/share/ 以下に置くことで、
    # 各モジュールから "pkgs.hyde の share/..." として参照できるようになる
    # BUILD FONTS
    mkdir -p $out/share/fonts/truetype
    for fontarchive in ./Source/arcs/Font_*.tar.gz; do
      if [ -f "$fontarchive" ]; then
        tar xzf "$fontarchive" -C $out/share/fonts/truetype/
      fi
    done

    # BUILD VSCODE EXTENSION
    mkdir -p $out/share/vscode/extensions/prasanthrangan.wallbash
    unzip ./Source/arcs/Code_Wallbash.vsix -d $out/share/vscode/extensions/prasanthrangan.wallbash
    # Ensure extension is readable and executable
    chmod -R a+rX $out/share/vscode/extensions/prasanthrangan.wallbash

    # BUILD GRUB THEMES
    mkdir -p $out/share/grub/themes
    tar xzf ./Source/arcs/Grub_Retroboot.tar.gz -C $out/share/grub/themes
    tar xzf ./Source/arcs/Grub_Pochita.tar.gz -C $out/share/grub/themes

    # BUILD ICONS
    mkdir -p $out/share/icons
    tar xzf ./Source/arcs/Icon_Wallbash.tar.gz -C $out/share/icons

    # BUILD GTK THEME
    mkdir -p $out/share/themes
    tar xzf ./Source/arcs/Gtk_Wallbash.tar.gz -C $out/share/themes

    runHook postBuild
  '';

  # 手直し済みのソースツリー「全体」を $out にコピーする。
  # これにより ${pkgs.hyde}/Configs/... という形で
  # HyDE の元のディレクトリ構造をそのまま参照できる
  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r . $out

    runHook postInstall
  '';

  # hyde-shell は Python スクリプトを呼ぶため、python3 と pyamdgpuinfo を
  # PATH / PYTHONPATH に注入したラッパーを被せる
  postInstall = ''
    wrapProgram $out/Configs/.local/bin/hyde-shell \
      --prefix PATH : "${pkgs.lib.makeBinPath [pkgs.python3]}" \
      --prefix PYTHONPATH : "${pkgs.python3.pkgs.makePythonPath [pkgs.pyamdgpuinfo]}" \
  '';

  meta = {
    description = "HyDE, your Development Environment";
    homepage = "https://github.com/HyDE-Project/HyDE";
    license = lib.licenses.gpl3Only;
    maintainers = [];
    platforms = lib.platforms.all;
  };
}
