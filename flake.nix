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

  inputs = {
    # URL はブランチを指し、実際の rev は flake.lock が固定する。
    # renovate の lockFileMaintenance が週 1 回 flake.lock を進める。
    # Hyprland も nixpkgs のものを使うので、Hyprland の flake は inputs に無い
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

    # nix-update は属性パスを JSON で書き出すときに非 ASCII 文字をエスケープし、
    # Nix がそれを別の名前として読んでしまう（"Rosé Pine" が見つからない）。
    # そのためテーマ名の非 ASCII 文字をそのまま渡すようにパッチを当てて使う
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
    # Hyprland comes from nixpkgs so its libraries stay consistent with the rest of the package set
    # pkgs/ の独自パッケージを pkgs に足す。
    # 以前は Hyprland の flake の overlay も重ねていたが、今は nixpkgs の Hyprland をそのまま使う
    overlays.default = import ./pkgs;

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
    # NixOS 以外でも home-manager 単体で使えるようにするための出力（フォークで追加）。
    # checks の hyprland-config と waybar-includes もこの構成を評価して使う
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
      inherit (pkgs) code-wallbash pyamdgpuinfo;
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
          runtimeInputs = [nix-update pkgs.git];
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
      # 対象はテーマ全部と、hyde-diff-upstream が使う HyDE master のビルド、hyprquery。
      # update-branch-pins.yml が毎週日曜に呼ぶ。
      # updateBranch が null ならリポジトリの既定ブランチを、そうでなければ指定のブランチを
      # --version=branch[=<名前>] で nix-update に渡し、rev と hash をまとめて書き換えさせる。
      # 途中で 1 つ失敗しても残りは続け、最後に失敗したものをログ付きで並べて非ゼロで終わる
      update-branch-pins = let
        # callPackage adds `override` and `overrideDerivation` alongside the themes
        themes = pkgs.lib.filterAttrs (_: pkgs.lib.isDerivation) pkgs.hydenix-themes;

        # Every commit pin that follows an upstream branch, keyed by the flake attribute path nix-update takes
        pins =
          pkgs.lib.mapAttrs' (name: theme: pkgs.lib.nameValuePair "legacyPackages.${system}.hydenix-themes.${builtins.toJSON name}" theme) themes
          // {
            "packages.${system}.hyde-diff-upstream.hyde-master" = inputs.self.packages.${system}.hyde-diff-upstream.hyde-master;
            "packages.${system}.hyprquery" = inputs.self.packages.${system}.hyprquery;
          };

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
    # 注: フォーマットチェックはコメントアウトされている。
    # CI は nix fmt を実行しないので、整形は各自が push 前に nix fmt を通す
    checks.${system} = {
      # "formatting" = treefmtEval.config.build.check inputs.self;
      inherit (pkgs) hyprquery hydectl hyde-config hyde code-wallbash Bibata-Modern-Ice Tela-circle-dracula;

      # hydenix が書き出す hyprland.lua で HyDE の Lua 設定を読み込めるかを確かめる。
      #   1. presets.nix の名前一覧が pkgs.hyde の実ファイルと一致するか
      #   2. ~/.config/hypr に置いた同名プリセットが HyDE のものより優先されるか
      #   3. activation と同じ hyde-shell <セレクタ> --set が通るか
      #   4. HYPRLAND_CONFIG を指定した起動と、指定しない起動の両方で
      #      Hyprland --verify-config が通るか
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

      # waybar.nix が HyDE の waybar.py で includes.json を生成するビルドそのものをチェックにする。
      # waybar.py の import や関数名が変われば、ここでビルドが失敗する
      # checks that HyDE's waybar.py still imports, still has update_icon_size and generate_includes, writes waybar/includes/includes.json, and lists modules from both module dirs
      waybar-includes = inputs.self.homeConfigurations.default.config.home.file.".config/waybar/includes/includes.json".source;

      # home.packages が全パッケージを 1 つのプロファイルへ束ねるのと同じことをする。
      # 単体のアイコン・カーソルテーマと、HyDE テーマに同梱されたコピーは
      # どちらも share/icons へ入るが、buildEnv は中身の食い違うディレクトリを
      # マージできない。既定のテーマ集合をここでビルドしておくことで、
      # 利用者の rebuild ではなく CI で衝突を捕まえる
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
