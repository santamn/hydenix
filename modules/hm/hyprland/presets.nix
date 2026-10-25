# The presets pkgs.hyde ships, so that a wrong name fails evaluation instead of the switch.
{
  # ~/.local/share/hypr/lua/animations/*.lua
  animations = [
    "00-disable"
    "01-default"
    "classic"
    "diablo-1"
    "diablo-2"
    "end4"
    "fast"
    "gnome"
    "ja"
    "limefrenzy"
    "macos"
    "me-1"
    "me-2"
    "minimal-2"
    "moving"
    "optimized"
    "standard"
    "vertical"
  ];

  # ~/.local/share/hypr/lua/workflows/*.lua
  workflows = [
    "01-default"
    "editing"
    "gaming"
    "powersaver"
    "snappy"
  ];

  # ~/.config/hypr/shaders/*.frag
  shaders = [
    "blue-light-filter"
    "color-vision"
    "custom"
    "disable"
    "grayscale"
    "invert-colors"
    "oled-saver"
    "paper"
    "vibrance"
    "wallbash"
  ];
}
