{
  description = "Language servers for opencode and Claude Code";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEach = f: nixpkgs.lib.genAttrs systems (system: f {
        # intelephense is unfree, so this set is imported with allowUnfree
        # rather than the flag being set globally in ~/.config/nixpkgs. The
        # permission stays scoped to this flake.
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      });
    in {
      packages = forEach ({ pkgs }: rec {
        # One derivation holding every server, so `nix profile install .#lsps`
        # installs or removes the whole set as a unit — which is what the
        # imperative one-at-a-time install could not give.
        lsps = pkgs.buildEnv {
          name = "lsp-servers";
          paths = with pkgs; [
            bash-language-server              # bash, sh, zsh
            vscode-langservers-extracted      # vscode-eslint-language-server, and json/html/css
            jdt-language-server               # java; pulls its own JDK
            kotlin-language-server
            nixd
            intelephense                      # php — unfree, hence allowUnfree above
            pyright                           # pyright-langserver
            rust-analyzer
            typescript-language-server
            vue-language-server
            yaml-language-server
          ];
        };
        default = lsps;
      });

      # `nix develop` for a shell that has them without touching the profile.
      devShells = forEach ({ pkgs }: {
        default = pkgs.mkShell {
          packages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.lsps ];
        };
      });
    };
}
