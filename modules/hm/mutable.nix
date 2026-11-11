# This module extends home.file, xdg.configFile and xdg.dataFile with the `mutable` option.
#
# =============================================================================
# home.file / xdg.configFile / xdg.dataFile に `mutable` オプションを追加する拡張
#
# ■ 何が問題なのか
#   home-manager は通常、設定ファイルを Nix ストアへのシンボリックリンクとして置く。
#   Nix ストアは読み取り専用なので、リンク先のファイルは書き換えられない。
#   ところが HyDE は「テーマを切り替えるとスクリプトが設定ファイルを書き換える」
#   という作りになっており、読み取り専用だと動作しない。
#
# ■ 解決策
#   `mutable = true;` を指定したファイルは、リンクを張った後に「コピー」で上書きし、
#   書き込み権限を付ける。これで HyDE のスクリプトが自由に書き換えられる。
#
# ■ 設定から外したとき
#   世代ごとに mutable なファイルの一覧（mutable-files）を残しておき、
#   新しい世代に無いコピーは古い世代へのリンクに戻す。すると home-manager が
#   普通のリンクと同じように削除する。手で書き換えた内容も一緒に消える。
#
# 仕組みの詳細は docs-ja/04-mutable-files.md を参照。
# =============================================================================
{
  config,
  lib,
  pkgs,
  ...
}: let
  # 既存の home.file などに mutable だけを追加定義する。
  # モジュールシステムは同じオプションの submodule 定義をマージするので、
  # 元の定義（source / text / force など）は壊れない
  mutableOption = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options.mutable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to copy the file without the read-only attribute instead of
          symlinking. If you set this to `true`, you must also set `force` to
          `true`. A mutable file is deleted once it is gone from your
          configuration, including any change you made to it after it was
          copied.

          This option is useful for programs that don't have a very good
          support for read-only configurations.
        '';
      };
    });
  };

  # xdg.configFile と xdg.dataFile は home.file に合流するので、home.file だけを見れば全部拾える
  # Home Manager merges xdg.configFile and xdg.dataFile into home.file.
  mutableFiles = lib.filter (file: file.enable && file.mutable) (lib.attrValues config.home.file);
in {
  options = {
    home.file = mutableOption;
    xdg.configFile = mutableOption;
    xdg.dataFile = mutableOption;
  };

  config = {
    # 前回コピーした実ファイルがホームに残っているので、force = true が無いと
    # 次の rebuild で home-manager の衝突チェックに引っかかる
    assertions =
      map (file: {
        assertion = file.force;
        message = "${file.target}: `mutable = true` requires `force = true`";
      })
      mutableFiles;

    # この世代でコピーする対象の一覧を、世代のディレクトリに mutable-files として書き出す。
    # 次の世代の mutableFileCleanup が「前回は mutable だったもの」を知るのにも使う。
    #
    # コピーは cp -L でリンクをたどるので、リンク先が Nix ストアの外（mkOutOfStoreSymlink など）なら
    # 実行するマシンにあるものがコピーされ、存在しなければ linkGeneration の後で activation が止まる。
    # checkMutableLinks はそうした世代をビルドの段階で失敗させ、どの世代にもロールバックできるようにする
    # The targets this generation copies, read by its own activation and by the next one.
    home.extraBuilderCommands = let
      manifest = pkgs.writeText "mutable-files" (lib.concatLines (map (file: file.target) mutableFiles));
    in ''
      ln -s ${manifest} $out/mutable-files

      function checkMutableLinks() {
        local target link resolved failed=0
        while IFS= read -r target; do
          while IFS= read -r -d "" link; do
            resolved="$(realpath -m -- "$link")"
            if [[ $resolved != ${builtins.storeDir}/* || ! -e $resolved ]]; then
              echo "error: the mutable file ~/''${link#"$out/home-files/"} links to $resolved, which is not an existing path in the Nix store" >&2
              failed=1
            fi
          done < <(find -L "$out/home-files/$target" -xtype l -print0)
        done < ${manifest}
        return "$failed"
      }

      checkMutableLinks
    '';

    # linkGeneration の前に実行する（ロールバック時は $oldGenPath が新しいほうの世代になる）。新しい世代でコピーされなくなったファイルを、
    # 古い世代へのリンクに戻しておく。こうすると linkGeneration が古いリンクの掃除として消すか、
    # 新しい世代のリンクに張り直す。
    #   - 新しい世代でも mutable なら、後のコピーで上書きされるので触らない
    #   - リンクに変わったファイルを手で書き換えていたら、home-manager の衝突チェックに任せる
    # Turns copies the new generation no longer makes back into links of the old generation,
    # so that linkGeneration deletes or relinks them like any other.
    home.activation.mutableFileCleanup = lib.hm.dag.entryBetween ["linkGeneration"] ["writeBoundary" "checkFilesChanged"] ''
      function relinkStaleMutableCopies() {
        if [[ ! -v oldGenPath || ! -e $oldGenPath/mutable-files ]]; then
          return
        fi

        local newGenFiles oldGenFiles
        newGenFiles="$(readlink -e "$newGenPath/home-files")"
        oldGenFiles="$(readlink -e "$oldGenPath/home-files")"

        local -A stillMutable=()
        local target
        while IFS= read -r target; do
          stillMutable[$target]=1
        done < "$newGenPath/mutable-files"

        local oldSource path
        while IFS= read -r target; do
          # Walk the old tree so that files the user added next to a recursive target's copies stay untouched.
          while IFS= read -r -d "" oldSource; do
            path="''${oldSource#"$oldGenFiles"/}"

            # Gone already, or still a link.
            if [[ ! -f $HOME/$path || -L $HOME/$path ]]; then
              continue
            fi

            if [[ -e $newGenFiles/$path ]]; then
              # Still mutable, so the copy step overwrites it.
              if [[ -n ''${stillMutable[$target]-} ]]; then
                continue
              fi
              # Now a link. An edited copy goes through Home Manager's collision handling instead.
              if ! cmp -s "$newGenFiles/$path" "$HOME/$path"; then
                continue
              fi
            fi

            run ln -sf $VERBOSE_ARG "$oldSource" "$HOME/$path"
          done < <(find "$oldGenFiles/$target" \( -type f -o -type l \) -print0)
        done < "$oldGenPath/mutable-files"
      }

      relinkStaleMutableCopies
    '';

    # リンクを張った後に、mutable なファイルをコピーで上書きする。
    #   -L : 世代のツリーはリンクなので、リンク先の中身をコピーする
    #   -T : ディレクトリ（recursive）の場合、linkGeneration が作ったディレクトリにマージする
    #   --remove-destination : 既存のシンボリックリンクを消してから書く
    #                          （これが無いとリンク先に書こうとして失敗する）
    # Nix ストアのファイルは読み取り専用なので、コピー後に chmod u+w で書き込み権限を付ける。
    # 実行権限は cp がそのまま引き継ぐ。
    #
    # このエントリ名 "mutableFileGeneration" は theme.nix / hyde.nix /
    # hyprland/ の各モジュールから entryAfter で参照されている。
    # home-manager の DAG は知らない依存名を黙って捨てるので、
    # 名前を変えるときは参照側も一緒に直すこと
    home.activation.mutableFileGeneration = lib.hm.dag.entryAfter ["linkGeneration"] ''
      function copyMutableFiles() {
        echo "Copying mutable home files for $HOME"

        local target
        while IFS= read -r target; do
          # -T merges a recursive target into the directory linkGeneration made.
          run cp -rLT --remove-destination "$newGenPath/home-files/$target" "$HOME/$target"
          # The store's modes are read-only.
          run chmod -R u+w "$HOME/$target"
        done < "$newGenPath/mutable-files"
      }

      copyMutableFiles
    '';
  };
}
