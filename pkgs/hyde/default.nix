# =============================================================================
# HyDE 本体を NixOS 向けにパッケージ化する
#
# HyDE はもともと Arch Linux 用の設定集なので、そのままでは動かない。
# buildPhase で次の 5 つを潰してから $out にまるごとコピーしている。
#
#   1. プロセス名の違い   … NixOS はラッパー経由で起動するので実名が .waybar-wrapped になる
#   2. シンボリックリンク … home-manager がリンクで配置するため find がたどれない
#   3. バイナリの入手方法 … Arch は pacman 前提。Nix パッケージ版に差し替える
#   4. Python インタプリタ … 実行時に uv で作る venv は NixOS では誰も作らない
#   5. 未展開のアーカイブ … アイコン、GTK テーマ、GRUB テーマが .tar.gz のまま同梱されている
#
# 詳細は docs-ja/03-hyde-package.md を参照。
# =============================================================================
{
  pkgs,
  lib,
  fetchFromGitHub,
  # interpreter for the Python scripts HyDE ships; override to add or drop libraries
  #
  # HyDE 同梱の Python スクリプトを動かすインタプリタ。
  # 上流は実行時に uv で venv ($XDG_STATE_HOME/hyde/python_env) を作る前提だが、
  # NixOS では誰もそれを作らないので、nixpkgs 側から渡す
  hydePython ?
    pkgs.python3.withPackages (
      ps:
        (with ps; [
          inotify-simple
          loguru
          pulsectl
          pygobject3
          pywayland
          requests
          xdg-base-dirs
        ])
        ++ [pkgs.pyamdgpuinfo]
    ),
}: let
  src = fetchFromGitHub {
    owner = "HyDE-Project";
    repo = "HyDE";
    rev = "v26.7.4";
    hash = "sha256-saNXLFMSi2MFRR/RyPGV2KWCKCJqjWRIKGDqdv+f5VE=";
  };
  version = lib.removePrefix "v" src.rev;
in
  pkgs.stdenv.mkDerivation {
    name = "hyde";
    inherit src version;

    nativeBuildInputs = with pkgs; [
      gnutar
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
      # 名前を置換して合わせる（waybar / dunst / kitty は killall の対象名、swaync は pgrep の照合名）
      find . -type f -print0 | xargs -0 sed -i 's/killall waybar/killall .waybar-wrapped/g'

      # update dunst
      find . -type f -print0 | xargs -0 sed -i 's/killall dunst/killall .dunst-wrapped/g'

      # update kitty
      find . -type f -print0 | xargs -0 sed -i 's/killall kitty/killall .kitty-wrapped/g'
      find . -type f -print0 | xargs -0 sed -i 's/killall -SIGUSR1 kitty/killall -SIGUSR1 .kitty-wrapped/g'

      # update swaync
      find . -type f -print0 | xargs -0 sed -i 's/pgrep -x swaync/pgrep -x .swaync-wrapped/g'

      # point the runtime uv venv interpreter path at hydePython
      #
      # 実行時 uv venv を指す参照を、すべて Nix のインタプリタへ向け直す。
      # hyde-shell (run_command) / gpuinfo.sh (AMD 分岐) / gamelauncher.sh は
      # "$XDG_STATE_HOME/hyde/python_env/bin/python" を直接 exec する。
      # そのパスは存在しないので、何も出力せずに死んで waybar のモジュールが空になっていた
      find . -type f -print0 | xargs -0 sed -i 's|''${XDG_STATE_HOME:-$HOME/\.local/state}/hyde/python_env/bin/python|${hydePython}/bin/python|g'

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
      # 各モジュールから "pkgs.hyde の share/..." として参照できるようになる。
      # フォントと VSCode 拡張は HyDE が 2026-07-27 のリリースで同梱をやめたので、ここでは扱わない。
      # フォントは modules/hm/hyde.nix が nixpkgs から、拡張は pkgs/code-wallbash.nix が入れる
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

    # inline the env instead of wrapProgram: hyde-shell is also sourced, and a wrapper's exec would kill the sourcing script
    #
    # hyde-shell は実行されるだけでなく、HyDE のスクリプトから source される。
    # hyprsunset.sh / hyprlock.sh / animations.sh / workflows.sh /
    # wallpaper.mpvpaper.sh はいずれも `source "$(which hyde-shell)"` で始まる。
    # wrapProgram のラッパーは最後に exec するため、source した側のプロセスが
    # 置き換わってしまい、これらのスクリプトは 1 行目で終了して何も出力しない
    postInstall = ''
      hydeShell=$out/Configs/.local/bin/hyde-shell
      {
        head -n 1 "$hydeShell"
        echo 'export PATH="${pkgs.lib.makeBinPath [hydePython]}:$PATH"'
        tail -n +2 "$hydeShell"
      } >"$hydeShell.new"
      mv "$hydeShell.new" "$hydeShell"
      chmod +x "$hydeShell"
    '';

    meta = {
      description = "HyDE, your Development Environment";
      homepage = "https://github.com/HyDE-Project/HyDE";
      license = lib.licenses.gpl3Only;
      maintainers = [];
      platforms = lib.platforms.all;
    };
  }
