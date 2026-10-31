{
  description = "Nix & home-manager configuration for HyDE, an Arch Linux based Hyprland desktop";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Home Manager (for user specific configuration)
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # NixOS hardware (for hardware profiles)
    nixos-hardware.url = "github:nixos/nixos-hardware";

    # Nix-index-database (for comma and command-not-found)
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    # treefmt (for formatting)
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: let
    system = "x86_64-linux";
    pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = [inputs.self.overlays.default];
    };

    # Eval the treefmt modules from ./treefmt.nix
    treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

    # Keep non-ASCII in theme names from being escaped into a form Nix misreads (e.g. "Rosé Pine" -> "Rosu00e9 Pine")
    nix-update = pkgs.nix-update.overrideAttrs (prev: {
      postPatch =
        (prev.postPatch or "")
        + ''
          substituteInPlace nix_update/options.py \
            --replace-fail '".".join(map(json.dumps, self.attribute_path))' \
              '".".join(json.dumps(part, ensure_ascii=False) for part in self.attribute_path)'
        '';
    });
  in {
    # Define custom NixOS modules
    nixosModules.default = {...}: {
      imports = [
        inputs.home-manager.nixosModules.home-manager
        ./modules/system
      ];

      home-manager.sharedModules = [
        inputs.nix-index-database.homeModules.nix-index
        inputs.self.homeModules.default
      ];
      nixpkgs.overlays = [inputs.self.overlays.default];
    };

    # Define custom NixOS modules
    homeModules.default = import ./modules/hm;

    # Define custom NixOS overlays
    # Hyprland comes from nixpkgs so its libraries stay consistent with the rest of the package set
    overlays.default = import ./pkgs;

    # for `nix build .#nixosConfigurations.<name>`
    nixosConfigurations.default = inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        inputs.self.nixosModules.default
        (inputs.nixpkgs + "/nixos/modules/profiles/minimal.nix")
        (inputs.nixpkgs + "/nixos/modules/profiles/qemu-guest.nix")
        ./demo
      ];
    };

    # for `home-manager switch --flake .#<name>`
    homeConfigurations.default = inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true; # for home
        overlays = [inputs.self.overlays.default];
      };
      modules = [
        inputs.nix-index-database.homeModules.nix-index
        inputs.self.homeModules.default
        ./demo/home.nix
      ];
    };

    # for `nix run .#<name>`
    packages.${system} = {
      # Use the VM configuration as default
      default = inputs.self.nixosConfigurations.default.config.system.build.vm;

      # Helper tools to manage HyDE updates by comparing the pinned package with upstream master
      hyde-diff-upstream = pkgs.callPackage ./pkgs/hyde-diff-upstream {};
      # Helper tool to manage HyDE updates by comparing the pinned package with a built home configuration
      hyde-diff-home = pkgs.callPackage ./pkgs/hyde-diff-home {};

      # Add hyprquery, hydectl, and hyde-config for building
      inherit (pkgs) hyprquery hydectl hyde-config hyde;
      inherit (pkgs) code-wallbash pokego pyamdgpuinfo;
    };

    # The update-branch-pins app passes each theme to nix-update using its flake attribute path.
    legacyPackages.${system} = {inherit (pkgs) hydenix-themes;};

    apps.${system} = {
      # for `nix run .#update-hashes`
      update-hashes = let
        # nix-update can only repair a package whose `src` is a fetcher
        updatable =
          pkgs.lib.filterAttrs
          (_: package: (package.src or null) ? outputHash)
          (removeAttrs inputs.self.packages.${system} ["default"]);
      in {
        type = "app";
        program = pkgs.lib.getExe (pkgs.writeShellApplication {
          name = "update-hashes";
          runtimeInputs = [nix-update pkgs.git];
          text = ''
            for attr in ${pkgs.lib.concatStringsSep " " (builtins.attrNames updatable)}; do
              nix-update "$attr" --flake --version=skip
            done
          '';
        });
      };

      # for `nix run .#update-branch-pins`
      update-branch-pins = let
        # callPackage adds `override` and `overrideDerivation` alongside the themes
        themes = pkgs.lib.filterAttrs (_: pkgs.lib.isDerivation) pkgs.hydenix-themes;

        # Every commit pin that follows an upstream branch, keyed by the flake attribute path nix-update takes
        pins =
          pkgs.lib.mapAttrs' (name: theme: pkgs.lib.nameValuePair "legacyPackages.${system}.hydenix-themes.${builtins.toJSON name}" theme) themes
          // {"packages.${system}.hyde-diff-upstream.hyde-master" = inputs.self.packages.${system}.hyde-diff-upstream.hyde-master;};

        # `rev` pins a commit, which cannot tell where newer ones are; the pin's branch does
        updatePin = attrPath: pin:
          pkgs.lib.escapeShellArgs [
            "update"
            attrPath
            (
              if pin.updateBranch == null
              then "branch"
              else "branch=${pin.updateBranch}"
            )
          ];
      in {
        type = "app";
        program = pkgs.lib.getExe (pkgs.writeShellApplication {
          name = "update-branch-pins";
          runtimeInputs = [nix-update pkgs.git];
          text = ''
            failed=()
            failureLog=$(mktemp)
            trap 'rm -f "$failureLog"' EXIT

            # One unreachable upstream must not hold back the rest, so collect and report at the end
            update() {
              local log
              log=$(mktemp)
              if ! nix-update "$1" --flake --version="$2" 2>&1 | tee "$log"; then
                failed+=("$1")
                {
                  printf '\n----- %s -----\n' "$1"
                  cat "$log"
                } >>"$failureLog"
              fi
              rm -f "$log"
            }

            ${pkgs.lib.concatStringsSep "\n" (pkgs.lib.mapAttrsToList updatePin pins)}

            if [ ''${#failed[@]} -gt 0 ]; then
              # Repeat the failures here; in a full run they are buried under the pins that worked
              printf 'could not update: %s\n' "''${failed[*]}" >&2
              cat "$failureLog" >&2
              exit 1
            fi
          '';
        });
      };
    };

    # for `nix flake check`
    checks.${system} = {
      # "formatting" = treefmtEval.config.build.check inputs.self;
      inherit (pkgs) hyprquery hydectl hyde-config hyde code-wallbash Bibata-Modern-Ice Tela-circle-dracula;

      # Hyprland loads HyDE's Lua config with the hyprland.lua hydenix writes, from both entry points a session can take
      hyprland-config = let
        inherit (inputs.self.homeConfigurations.default) config;
        cfg = config.hydenix.hm.hyprland;
        hydeShell = "${pkgs.hyde}/Configs/.local/bin/hyde-shell";
        presets = import ./modules/hm/hyprland/presets.nix;
        # The preset names the modules accept must be the ones pkgs.hyde ships
        sameNames = names: dir: ext: "diff <(printf '%s\\n' ${toString names}) <(ls ${dir} | sed -n 's/\\${ext}$//p')";
      in
        pkgs.runCommand "hyprland-config" {nativeBuildInputs = [pkgs.hyprland];} ''
          ${sameNames presets.animations "${pkgs.hyde}/Configs/.local/share/hypr/lua/animations" ".lua"}
          ${sameNames presets.workflows "${pkgs.hyde}/Configs/.local/share/hypr/lua/workflows" ".lua"}
          ${sameNames presets.shaders "${pkgs.hyde}/Configs/.config/hypr/shaders" ".frag"}

          export HOME=$PWD/home XDG_RUNTIME_DIR=$PWD/run
          mkdir -p $HOME/.config/hypr $HOME/.local/lib $HOME/.local/share $XDG_RUNTIME_DIR
          ln -s ${pkgs.hyde}/Configs/.local/lib/hyde $HOME/.local/lib/hyde
          ln -s ${pkgs.hyde}/Configs/.local/share/hypr $HOME/.local/share/hypr
          ln -s ${pkgs.hyde}/Configs/.config/hypr/shaders $HOME/.config/hypr/shaders
          ln -s ${config.home.file.".config/hypr/hyprland.lua".source} $HOME/.config/hypr/hyprland.lua

          # A preset under ~/.config/hypr replaces HyDE's one of the same name
          mkdir -p $HOME/.config/hypr/lua/animations
          cp $HOME/.local/share/hypr/lua/animations/standard.lua $HOME/.config/hypr/lua/animations/
          ${hydeShell} animations --set standard
          grep -qF $HOME/.config/hypr/lua/animations/standard.lua $HOME/.local/state/hyde/lua_state/animations.lua

          # What activation runs; the selectors and open.lua load hydeLua's rocks and lgi, and Hyprland loads the state they write
          ${hydeShell} animations --set ${cfg.animations.preset}
          ${hydeShell} workflows --set ${cfg.workflows.active}
          ${hydeShell} shaders --set ${cfg.shaders.active}
          ${hydeShell} open --help >/dev/null

          HYPRLAND_CONFIG=$HOME/.local/share/hypr/hyde.lua Hyprland --verify-config
          Hyprland --verify-config
          touch $out
        '';

      # mirror the `home.packages` buildEnv merge over the default `hydenix.hm.theme.themes`.
      # `altIcons` pulls in the whole asset tree, so this builds the merge as well
      theme-assets = pkgs.buildEnv {
        name = "hydenix-theme-assets";
        paths = with pkgs; [
          Bibata-Modern-Ice
          Tela-circle-dracula
          (hydenix-theme-assets [
            hydenix-themes."Catppuccin Mocha"
            hydenix-themes."Catppuccin Latte"
          ])
          .altIcons
        ];
      };
    };

    # for `nix fmt`
    formatter.${system} = treefmtEval.config.build.wrapper;

    # for `nix develop`
    devShells.${system}.default = pkgs.callPackage ./shell.nix {};

    # for `nix flake new -t <template>`
    templates.default = {
      path = ./template;
      description = "Template for hydenix configuration";
    };
  };
}
