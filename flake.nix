# =============================================================================
# hydenix の入口。依存 (inputs) と、外部に公開するもの (outputs) を宣言する。
#
# 利用者が実際に使うのは次の 3 つだけで、ファイル配置には関与しない。
#   inputs.hydenix.nixosModules.default  … システム側モジュール一式
#   inputs.hydenix.homeModules.default   … ユーザー側モジュール一式
#   inputs.hydenix.overlays.default      … pkgs.hyde などを pkgs に追加
#
# 全体像は docs-ja/01-architecture.md を参照。
# =============================================================================
{
  description = "Nix & home-manager configuration for HyDE, an Arch Linux based Hyprland desktop";

  # このリポジトリを flake として使ったときに追加されるバイナリキャッシュ。
  # Hyprland を自前ビルドすると非常に重いので、これがあると助かる
  nixConfig = {
    extra-substituters = ["https://hyprland.cachix.org"];
    extra-trusted-substituters = ["https://hyprland.cachix.org"];
    extra-trusted-public-keys = ["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="];
  };

  inputs = {
    # nixpkgs はコミットハッシュで固定している。
    # HyDE / Hyprland との組み合わせを検証済みの状態に固定するのが目的で、
    # 更新は renovate と update-flake-lock ワークフローが自動で行う
    nixpkgs.url = "github:nixos/nixpkgs/61b7c44c4073f0b827768aff0049561b5110ea5a";

    # Home Manager (for user specific configuration)
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # NixOS hardware (for hardware profiles)
    nixos-hardware.url = "github:nixos/nixos-hardware";

    # Hyprland (pin it to the latest version supported by HyDE)
    hyprland.url = "github:hyprwm/Hyprland/v0.55.4";

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
    #
    # 利用者はこれ 1 つを imports に足すだけでよい。
    # home-manager 本体の読み込みと、homeModules.default の配線
    # （sharedModules = 全ユーザーに適用されるモジュール）まで面倒を見てくれる。
    # 本家では利用者が自分で書く必要があった部分
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
    # Hyprland の flake から来るパッケージ群と、pkgs/ の独自パッケージを合成する。
    # `//` は属性集合の上書きマージなので、同名なら pkgs/ 側が勝つ
    overlays.default = final: prev:
      (inputs.hyprland.overlays.hyprland-packages final prev)
      // (import ./pkgs final prev);

    # for `nix build .#nixosConfigurations.<name>`
    # 動作確認用のデモ構成（demo/）。`nix run .` で VM が起動する
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
    # NixOS 以外でも home-manager 単体で使えるようにするための出力（フォークで追加）
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
      inherit (pkgs) hyprquery hydectl hyde-config hyde-ipc hyde hyde-gallery;
      inherit (pkgs) pokego pyamdgpuinfo;
    };

    # for `nix flake check`
    # 注: フォーマットチェックはコメントアウトされている。
    # 整形は CI 側（flint / treefmt）に任せる方針
    checks.${system} = {
      # "formatting" = treefmtEval.config.build.check inputs.self;
      inherit (pkgs) hyprquery hydectl hyde-config hyde-ipc;
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
