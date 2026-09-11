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
    # URL はブランチを指し、実際の rev は flake.lock が固定する。
    # renovate の lockFileMaintenance が週 1 回 flake.lock を進める。
    # 以前は rev を URL に直書きしていたが、それだと `nix flake update` で動かせなかった
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
      inherit (pkgs) hyprquery hydectl hyde-config hyde-ipc hyde;
      inherit (pkgs) code-wallbash pokego pyamdgpuinfo;
    };

    # The update-branch-pins app passes each theme to nix-update using its flake attribute path.
    #
    # nix-update はパッケージを flake の属性パスで受け取る。
    # packages には derivation しか置けず、テーマの集合（属性集合）は入らないので、
    # legacyPackages から `legacyPackages.<system>.hydenix-themes."<テーマ名>"` として公開する
    legacyPackages.${system} = {inherit (pkgs) hydenix-themes;};

    # 依存の更新に使う 2 つのコマンド。
    # 何を更新するかを nix の評価で決めるので、呼ぶ側は属性名もバージョンも知らなくてよい
    apps.${system} = {
      # for `nix run .#update-hashes`
      #
      # rev を書き換えたあと、古くなった hash を計算し直す。
      # renovate が pkgs/ の rev を上げたときも postUpgradeTasks でこれを呼ぶ。
      # src が fetcher（outputHash を持つ）のパッケージだけを対象にし、
      # --version=skip で rev には触らない
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
      #
      # ブランチを追っている commit 固定を、そのブランチの先頭まで進める。
      # 対象はテーマ全部と、hyde-diff-upstream が使う HyDE master のビルド。
      # update-branch-pins.yml が毎晩呼ぶ。
      # updateBranch が null ならリポジトリの既定ブランチを、そうでなければ指定のブランチを
      # --version=branch[=<名前>] で nix-update に渡し、rev と sha256 をまとめて書き換えさせる。
      # 途中で 1 つ失敗しても残りは続け、最後に失敗したものを並べて非ゼロで終わる
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
          runtimeInputs = [pkgs.nix-update pkgs.git];
          text = ''
            failed=()

            # One unreachable upstream must not hold back the rest, so collect and report at the end
            update() {
              nix-update "$1" --flake --version="$2" || failed+=("$1")
            }

            ${pkgs.lib.concatStringsSep "\n" (pkgs.lib.mapAttrsToList updatePin pins)}

            if [ ''${#failed[@]} -gt 0 ]; then
              printf 'could not update: %s\n' "''${failed[*]}" >&2
              exit 1
            fi
          '';
        });
      };
    };

    # for `nix flake check`
    # 注: フォーマットチェックはコメントアウトされている。
    # 整形は CI 側（flint / treefmt）に任せる方針
    checks.${system} = {
      # "formatting" = treefmtEval.config.build.check inputs.self;
      inherit (pkgs) hyprquery hydectl hyde-config hyde-ipc hyde code-wallbash Bibata-Modern-Ice Tela-circle-dracula;

      # mirror the `home.packages` buildEnv merge over the default `hydenix.hm.theme.themes`
      #
      # home.packages が全パッケージを 1 つのプロファイルへ束ねるのと同じことをする。
      # 単体のアイコン・カーソルテーマと、HyDE テーマに同梱されたコピーは
      # どちらも share/icons へ入るが、buildEnv は中身の食い違うディレクトリを
      # マージできない。既定のテーマ集合をここでビルドしておくことで、
      # 利用者の rebuild ではなく CI で衝突を捕まえる
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
