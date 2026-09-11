# =============================================================================
# テーマ 1 つをビルドする関数（カリー化: 先に pkgs、後からテーマ情報を渡す）
#
# 出来上がるパッケージのレイアウト:
#   $out/share/hyde/themes/<テーマ名>/  … HyDE が読む設定一式（wallbash の色定義など）
#   $out/share/themes/                  … GTK テーマ
#   $out/share/icons/                   … アイコン・カーソルテーマ
#   $out/share/fonts/                   … フォント
#
# テーマによって同梱物が違うため、どの展開処理も
# 「あれば入れる、無ければ飛ばす」という書き方になっている。
# =============================================================================
{
  pkgs,
  # Standalone icon/cursor theme packages, keyed by the directory name their bundled tarball unpacks to
  #
  # hydenix が単体パッケージとしても配布しているアイコン・カーソルテーマ。
  # キーは HyDE の同梱 tarball が展開されるディレクトリ名。詳細は `relinkShared` を参照。
  # 既定値を持たない必須引数なので、渡し忘れると eval エラーになる
  sharedAssets,
}: {
  name,
  src,
  # テーマが追っているブランチ。1 つのリポジトリにテーマをブランチ別に置いているテーマだけが指定し、
  # それ以外は null（リポジトリの既定ブランチを追う）。
  # update-branch-pins が passthru.updateBranch 経由で読む
  branch ? null,
  meta,
} @ args: let
  # Replace bundled copies of shared assets with symlinks so both providers resolve to one store path
  relinkShared = pkgs.lib.concatMapStringsSep "\n" (assetName: ''
    if [ -e "$out/share/icons/${assetName}" ]; then
      echo "Using the standalone ${assetName} package instead of the bundled copy"
      rm -rf "$out/share/icons/${assetName}"
      ln -s "${sharedAssets.${assetName}}/share/icons/${assetName}" "$out/share/icons/${assetName}"
    fi
  '') (builtins.attrNames sharedAssets);

  # Helper function to find the first directory in a path
  findFirstDir = ''
    findFirstDir() {
      local path="$1"
      if [ -d "$path" ]; then
        local first_dir=$(find "$path" -mindepth 1 -maxdepth 1 -type d | head -n 1)
        if [ -n "$first_dir" ]; then
          basename "$first_dir"
        else
          echo ""
        fi
      else
        echo ""
      fi
    }
  '';

  # The build recipe every theme shares; the per-theme attrs come straight from the caller
  buildAttrs = {
    pname = name;
    passthru.updateBranch = branch;
    version = "1.0.0";

    nativeBuildInputs = with pkgs; [
      gnutar
    ];

    # Nix が実行ファイル向けに行う後処理を無効化する指定。
    # テーマは素材の集まりなので、これらの処理はむしろ壊す原因になる
    dontPatchELF = true;
    dontRewriteSymlinks = true;
    dontDropIconThemeCache = true;

    installPhase = ''
      runHook preInstall

      # Create theme directory structure
      mkdir -p $out/share/hyde/themes/"${name}"
      mkdir -p $out/share/themes
      mkdir -p $out/share/icons
      mkdir -p $out/share/fonts

      ${findFirstDir}

      cp -r Configs/.config/hyde/themes/"${name}"/. $out/share/hyde/themes/"${name}"/

      # Install GTK theme if available
      for gtk_archive in ./Source/arcs/Gtk_* ./Source/Gtk_*; do
        if [ -f "$gtk_archive" ]; then
          echo "Installing GTK theme from: $gtk_archive"
          tar -xf "$gtk_archive" -C $out/share/themes
          break
        fi
      done

      # Install icon theme if available
      for icon_archive in ./Source/arcs/Icon_* ./Source/Icon_*; do
        if [ -f "$icon_archive" ]; then
          echo "Installing icon theme from: $icon_archive"
          tar -xf "$icon_archive" --skip-old-files -C $out/share/icons

          ICON_DIR=$(findFirstDir $out/share/icons)
          echo "Icon directory: $ICON_DIR"

          # Only process broken symlinks if the icon directory exists
          if [ -n "$ICON_DIR" ] && [ -d "$out/share/icons/$ICON_DIR" ]; then
            # Fix broken symlinks in icon theme - limit to a reasonable depth
            find "$out/share/icons/$ICON_DIR" -maxdepth 5 -type l | while read -r link; do
              target=$(readlink "$link")
              if [[ "$target" == /* ]]; then
                # Skip absolute links
                continue
              fi

              target_path="$(dirname "$link")/$target"
              if [ ! -e "$target_path" ]; then
                rm "$link"
              fi
            done
          fi
          break
        fi
      done

      # Install cursor theme if available
      for cursor_archive in ./Source/arcs/Cursor_* ./Source/Cursor_*; do
        if [ -f "$cursor_archive" ]; then
          echo "Installing cursor theme from: $cursor_archive"
          tar -xf "$cursor_archive" --skip-old-files -C $out/share/icons
          break
        fi
      done

      ${relinkShared}

      # Install font if available
      for font_archive in ./Source/arcs/Font_* ./Source/Font_*; do
        if [ -f "$font_archive" ]; then
          echo "Installing font from: $font_archive"
          mkdir -p $out/share/fonts
          tar -xf "$font_archive" -C $out/share/fonts || echo "Warning: Failed to extract font archive $font_archive. Skipping."
          break
        fi
      done

      runHook postInstall
    '';

    meta = with pkgs.lib;
      {
        license = licenses.mit;
        platforms = platforms.all;
      }
      // meta;
  };

  # The theme package combines its HyDE config with the GTK, icon, cursor, and font archives it ships.
  # `src` must be passed via `args` instead of using `inherit src` here: nix-update rewrites `rev` and `sha256` in whichever file defines `src`, which must be the theme file rather than this helper.
  # `branch` is dropped because only the updater needs it, and having it as a derivation attr would change the hash of every theme that sets it.
  #
  # テーマファイルが渡した属性をそのまま mkDerivation に通す。
  # nix-update は src が定義されている位置のファイルを書き換えるので、ここで `inherit src` すると
  # テーマファイルではなくこの共通関数が書き換え対象になってしまう。
  # branch は更新ツールしか使わないので derivation には入れない。入れると branch を持つテーマのハッシュが変わる
  pkg = pkgs.stdenv.mkDerivation (builtins.removeAttrs args ["branch"] // buildAttrs);
in
  pkg
