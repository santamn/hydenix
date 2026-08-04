{
  lib,
  runCommand,
  bibata-cursors,
  hyprcursor,
  xcur2png,
}:
runCommand "Bibata-Modern-Ice-${bibata-cursors.version}" {
  nativeBuildInputs = [hyprcursor xcur2png];

  meta = {
    description = "Bibata Modern Ice cursor theme, with hyprcursor variant";
    homepage = "https://github.com/ful1e5/Bibata_Cursor";
    license = lib.licenses.gpl3Only;
    maintainers = [];
    platforms = lib.platforms.linux;
  };
} ''
  xcursor=${bibata-cursors}/share/icons/Bibata-Modern-Ice
  theme=$out/share/icons/Bibata-Modern-Ice

  mkdir -p $out/share/icons
  cp -r "$xcursor" $out/share/icons/
  chmod -R u+w "$theme"

  # nixpkgs builds XCursor only, so rebuild the hyprcursor variant from it
  hyprcursor-util --extract "$xcursor" --output "$TMPDIR" --resize bilinear
  substituteInPlace "$TMPDIR/extracted_Bibata-Modern-Ice/manifest.hl" \
    --replace-fail "name = Extracted Theme" "name = Bibata-Modern-Ice" \
    --replace-fail "version = 0.1" "version = ${bibata-cursors.version}"
  hyprcursor-util --create "$TMPDIR/extracted_Bibata-Modern-Ice" --output "$TMPDIR"

  cp "$TMPDIR/theme_Bibata-Modern-Ice/manifest.hl" "$theme/"
  cp -r "$TMPDIR/theme_Bibata-Modern-Ice/hyprcursors" "$theme/"
''
