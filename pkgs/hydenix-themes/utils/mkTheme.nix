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
  # hydenix が単体パッケージとしても配布しているアイコン・カーソルテーマ。
  # キーは HyDE の同梱 tarball が展開されるディレクトリ名。詳細は `relinkShared` を参照
  sharedAssets ? {},
}: {
  name,
  src,
  meta,
}: let
  /*
  HyDE themes bundle their icon/cursor themes as tarballs, and some of them
  carry a theme hydenix already installs on its own -- Catppuccin Mocha ships
  Tela-circle-dracula, for instance. Since hydenix builds those from nixpkgs
  sources rather than from HyDE's tarballs, the two copies of
  `share/icons/<name>` differ, and home-manager's `buildEnv` aborts with a
  collision as soon as both land in `home.packages`.

  Replacing the bundled copy with a symlink to the standalone package keeps the
  theme self-contained while making both paths resolve to the same store path,
  which `buildEnv` accepts.
  */
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

  # Combined theme package that includes all arcs
  pkg = pkgs.stdenv.mkDerivation {
    inherit name src;
    pname = name;

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

    # No theme sets `priority`, so it must not be inherited unconditionally:
    # `buildEnv` reads `meta.priority or <default>`, and an attribute that is
    # present but throws when forced defeats the `or` fallback.
    meta = with pkgs.lib;
      {
        license = licenses.mit;
        platforms = platforms.all;
      }
      // meta;
  };
in
  pkg
