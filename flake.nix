{
  description = "Nix & home-manager configuration for HyDE, an Arch Linux based Hyprland desktop";

  nixConfig = {
    extra-substituters = ["https://hyprland.cachix.org"];
    extra-trusted-substituters = ["https://hyprland.cachix.org"];
    extra-trusted-public-keys = ["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Home Manager (for user specific configuration)
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # NixOS hardware (for hardware profiles)
    nixos-hardware.url = "github:nixos/nixos-hardware";

    # Hyprland (pin it to the latest version supported by HyDE)
    hyprland.url = "github:hyprwm/Hyprland/v0.56.2";

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
    overlays.default = final: prev:
      (inputs.hyprland.overlays.hyprland-packages final prev)
      // (import ./pkgs final prev);

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

      # Add hyprquery, hydectl, hyde-ipc, and hyde-config for building
      inherit (pkgs) hyprquery hydectl hyde-config hyde-ipc hyde;
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
          runtimeInputs = [pkgs.nix-update pkgs.git];
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

        # `rev` pins a commit, which cannot tell where newer ones are; the theme's branch does
        updateTheme = name: theme:
          pkgs.lib.escapeShellArgs [
            "update"
            "legacyPackages.${system}.hydenix-themes.${builtins.toJSON name}"
            (
              if theme.updateBranch == null
              then "branch"
              else "branch=${theme.updateBranch}"
            )
          ];
      in {
        type = "app";
        program = pkgs.lib.getExe (pkgs.writeShellApplication {
          name = "update-branch-pins";
          runtimeInputs = [pkgs.nix-update pkgs.git];
          text = ''
            failed=()

            # One unreachable upstream must not hold back the rest, so collect and report at the end
            update() {
              nix-update "$1" --flake --version="$2" || failed+=("$1")
            }

            ${pkgs.lib.concatStringsSep "\n" (pkgs.lib.mapAttrsToList updateTheme themes)}

            if [ ''${#failed[@]} -gt 0 ]; then
              printf 'could not update: %s\n' "''${failed[*]}" >&2
              exit 1
            fi
          '';
        });
      };
    };

    # for `nix flake check`
    checks.${system} = {
      # "formatting" = treefmtEval.config.build.check inputs.self;
      inherit (pkgs) hyprquery hydectl hyde-config hyde-ipc hyde code-wallbash Bibata-Modern-Ice Tela-circle-dracula;

      # mirror the `home.packages` buildEnv merge over the default `hydenix.hm.theme.themes`
      theme-assets = pkgs.buildEnv {
        name = "hydenix-theme-assets";
        paths = with pkgs; [
          Bibata-Modern-Ice
          Tela-circle-dracula
          hydenix-themes."Catppuccin Mocha"
          hydenix-themes."Catppuccin Latte"
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
