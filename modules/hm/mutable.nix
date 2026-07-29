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
#   `mutable = true;` を指定したファイルは、リンクではなく「コピー」で配置し、
#   書き込み権限を付ける。これで HyDE のスクリプトが自由に書き換えられる。
#
# ■ 代償
#   コピーなので home-manager の管理から外れる。設定から削除しても
#   ホームディレクトリに残り続けるため、手動で消す必要がある。
#
# 仕組みの詳細は docs-ja/04-mutable-files.md を参照。
# =============================================================================
{
  config,
  lib,
  pkgs,
  ...
}: let
  # 拡張対象となる 3 つのオプション。属性パスをリストで表現している
  #   [ "home" "file" ] は config.home.file を指す
  fileOptionAttrPaths = [
    [
      "home"
      "file"
    ]
    [
      "xdg"
      "configFile"
    ]
    [
      "xdg"
      "dataFile"
    ]
  ];
in {
  # ---------------------------------------------------------------------------
  # options: 3 つのオプションそれぞれに `mutable` サブオプションを生やす
  #
  # NixOS のモジュールシステムでは、同じオプションを複数のモジュールが定義すると
  # 「マージ」される。ここでは既存の home.file 等に対して mutable だけを
  # 追加定義することで、元の定義を壊さずに項目を増やしている。
  # ---------------------------------------------------------------------------
  options = let
    # 属性集合のリストを 1 つにまとめる（foldl' で順に mergeAttrs していく）
    mergeAttrsList = builtins.foldl' lib.mergeAttrs {};

    # 「ファイル名 → 設定」の属性集合の型。
    # submodule は「入れ子の設定オブジェクト」を表す型で、
    # ここでは mutable という bool 項目だけを追加している
    fileAttrsType = lib.types.attrsOf (
      lib.types.submodule (
        _: {
          options.mutable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Whether to copy the file without the read-only attribute instead of
              symlinking. If you set this to `true`, you must also set `force` to
              `true`. Mutable files are not removed when you remove them from your
              configuration.

              This option is useful for programs that don't have a very good
              support for read-only configurations.
            '';
          };
        }
      )
    );
  in
    # fileOptionAttrPaths の各パスに対して
    #   { home.file = mkOption {...}; } のような属性集合を作り、すべて統合する
    mergeAttrsList (
      map (
        attrPath: lib.setAttrByPath attrPath (lib.mkOption {type = fileAttrsType;})
      )
      fileOptionAttrPaths
    );

  # ---------------------------------------------------------------------------
  # config: mutable 指定のファイルを実際にコピーする activation スクリプトを生成
  #
  # 注意: この config は enable フラグで囲われていない（無条件）。
  # そのため mutableFileGeneration というエントリは常に存在する
  # ---------------------------------------------------------------------------
  config = {
    home.packages = with pkgs; [
      file # ファイル種別の判定（実行ファイルかどうかの判別に使う）
      findutils # find コマンド
    ];

    home.activation.mutableFileGeneration = let
      # 3 つのオプションに登録された全ファイル定義を 1 つのリストに集める
      allFiles = builtins.concatLists (
        map (attrPath: builtins.attrValues (lib.getAttrFromPath attrPath config)) fileOptionAttrPaths
      );

      # mutable = true のものだけを抽出する。
      # このとき force = true でなければ assertMsg がエラーを出して停止する
      # （force が無いと home-manager 側のリンク作成と衝突するため）
      filterMutableFiles = builtins.filter (
        file:
          (file.mutable or false)
          && lib.assertMsg file.force "if you specify `mutable` to `true` on a file, you must also set `force` to `true`"
      );

      mutableFiles = filterMutableFiles allFiles;

      # ファイル定義 1 つを、コピー用のシェルスクリプト断片に変換する関数
      toCommand = file: let
        # escapeShellArg: パスに空白などが含まれていても壊れないようクォートする
        source = lib.escapeShellArg file.source;
        target = lib.escapeShellArg file.target;
        recursiveFlag =
          if (file.recursive or false)
          then "-r"
          else "";
      in ''
        $VERBOSE_ECHO "Copying mutable file: ${source} -> ${target}"

        # --remove-destination : 既存のシンボリックリンクを消してから書く
        #                        （これが無いとリンク先に書こうとして失敗する）
        # --no-preserve=mode   : Nix ストアの読み取り専用パーミッションを引き継がない
        #                        （こちらが本質）
        if [ -n "${recursiveFlag}" ]; then
          $DRY_RUN_CMD cp -r --remove-destination --no-preserve=mode ${source}/. ${target} || {
            echo "Error: Failed to copy recursive directory ${source} to ${target}"
            exit 1
          }
        else
          $DRY_RUN_CMD cp --remove-destination --no-preserve=mode ${source} ${target} || {
            echo "Error: Failed to copy file ${source} to ${target}"
            exit 1
          }
        fi

        # コピーしたものがスクリプトなら実行権限を付け直す
        # （HyDE は ~/.local/lib/hyde 以下のスクリプトを実行するため必須）
        if [ -d ${target} ]; then
          find ${target} -type f -exec sh -c '
            for f do
              type=$(${pkgs.file}/bin/file -b "$f")
              if echo "$type" | grep -qE "executable|script" || [[ "$f" =~ \.sh$ ]]; then
                $DRY_RUN_CMD chmod u+wx "$f" || {
                  echo "Error: Failed to set permissions on $f"
                  exit 1
                }
              fi
            done
          ' sh {} +
        else
          type=$(${pkgs.file}/bin/file -b ${target})
          if echo "$type" | grep -qE "executable|script" || [[ ${target} =~ \.sh$ ]]; then
            $DRY_RUN_CMD chmod u+wx ${target} || {
              echo "Error: Failed to set permissions on ${target}"
              exit 1
            }
          fi
        fi
      '';

      # 全 mutable ファイル分のコマンドを連結して 1 本のスクリプトにする
      command =
        ''
          export PATH="${pkgs.file}/bin:${pkgs.findutils}/bin:$PATH"
          echo "Copying mutable home files for $HOME"
        ''
        + lib.concatLines (map toCommand mutableFiles);
    in
      # DAG (依存グラフ) 上で "linkGeneration"（home-manager が
      # シンボリックリンクを張る処理）の直後に実行するよう指定する。
      # 「リンクを張った後にコピーで上書きする」という順序が重要。
      #
      # 注意: 他モジュール（theme.nix / hyde.nix / hyprland/default.nix）は
      # ここのエントリ名を "mutableGeneration" と誤って参照している。
      # 詳細は docs-ja/08-improvements.md を参照
      lib.hm.dag.entryAfter ["linkGeneration"] command;
  };
}
