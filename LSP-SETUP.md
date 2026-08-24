# Language server setup — opencode (and what's possible for Claude Code)

Installs eleven language servers from one Nix flake and wires them into opencode:
bash, eslint, jdtls, kotlin, nixd, intelephense (PHP), pyright, rust-analyzer,
typescript, vue, yaml.

Everything below was executed and verified on x86_64-linux before being written
down. The two places where I could not verify are called out as such.

## 0. Prerequisites

- Nix with flakes enabled. Check:

      nix --version
      nix flake --help >/dev/null 2>&1 && echo "flakes ok" || echo "enable nix-command,flakes"

  If flakes are off, add to `~/.config/nix/nix.conf`:

      experimental-features = nix-command flakes

- `jq` on PATH (step 3 uses it).
- Roughly 2.5 GB of store space: jdt-language-server pulls its own JDK.

## 1. flake.nix

Put this in a directory of its own, e.g. `~/nix/lsps/flake.nix`.

```nix
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
        # installs or removes the whole set as a unit.
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
```

## 2. Build and install

    cd ~/nix/lsps
    nix build --no-link --print-out-paths .#lsps    # verify it evaluates and builds
    nix profile install .#lsps                      # then put it on PATH

`allowUnfree` is set inside the flake, so **no** `NIXPKGS_ALLOW_UNFREE=1` and no
`--impure` is needed. That scoping is deliberate: it does not grant unfree
permission to anything else you build on the machine.

If the profile already contains any of these servers installed individually,
remove them first or the install collides on `bin/` symlinks:

    nix profile list | grep -Ei 'language-server|intelephense|pyright|rust-analyzer|nixd|jdt'
    nix profile remove <name> ...

### Verify — do this before touching any config

    for b in bash-language-server vscode-eslint-language-server jdtls \
             kotlin-language-server nixd intelephense pyright-langserver \
             rust-analyzer typescript-language-server vue-language-server \
             yaml-language-server; do
      command -v "$b" >/dev/null && printf '  %-32s ok\n' "$b" \
                                 || printf '  %-32s MISSING\n' "$b"
    done

All eleven must say `ok`. Expect `~/.nix-profile/bin/*` — use that path in the
config, not the `/nix/store/...` path, so upgrades don't strand the config.

**Do not use `--version` to test these.** `intelephense --version` is not a
supported flag; it prints its own bundled JavaScript source — tens of thousands
of lines. To actually prove a server speaks LSP, hand it an `initialize`:

    body='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{}}}'
    { printf 'Content-Length: %d\r\n\r\n%s' "${#body}" "$body"; sleep 6; } \
      | timeout 20 intelephense --stdio 2>&1 | head -c 200

A healthy server answers with `Content-Length:` framing and JSON-RPC. Note the
`sleep` — without it stdin closes and the server exits before replying, which
looks identical to a broken binary.

## 3. Wire it into opencode

opencode's `lsp` key is an **object keyed by server name**; each value needs
`command` (argv array, absolute path) and optionally `extensions`, `env`,
`initialization`, `disabled`.

Use the generator (`gen-lsp-config.sh`, alongside this file). It writes only the
`lsp` key, preserves every other key, backs up first, and refuses to run if any
binary is missing or the existing config is not valid JSON:

    BIN="$HOME/.nix-profile/bin" ./gen-lsp-config.sh

Verified here against the built environment: `wrote 11 servers`, with
`$schema` and `model` untouched.

Check afterwards:

    jq -r '.lsp | to_entries[] | "\(.key): \(.value.command[0])"' ~/.config/opencode/opencode.json
    jq -r 'keys | join(", ")' ~/.config/opencode/opencode.json

If you would rather hand-edit, the two non-obvious argv shapes are
`bash-language-server start` (subcommand, not `--stdio`) and bare `jdtls`,
`kotlin-language-server`, `nixd`, `rust-analyzer` (no flag at all). The other
six take `--stdio`.

## 4. Claude Code

**There is no settings key for language servers.** Claude Code has an internal
LSP layer — `--bare` skips it — but it is not user-configurable the way
opencode's `lsp` block is, so the eleven servers cannot be registered with it
the same way. Installing them still helps anything else on the box that
discovers servers on PATH.

I could not verify any supported mechanism for pointing Claude Code at these.
Do not invent a config key for it; if this matters, confirm against current
Claude Code docs rather than trusting this paragraph.

## 5. Gotchas

- **Version lag.** nixpkgs `intelephense` was 1.18.2 where npm/bun had 1.18.5.
  Patch-level, but if PHP intel regresses this is the first thing to check.
- **Don't run two copies.** If a server is also installed via npm/bun/cargo,
  whichever comes first on PATH wins and it may not be the one in your config.
  Check with `command -v <binary>` and remove the loser
  (`bun remove -g <pkg>`, `npm rm -g <pkg>`, `cargo uninstall <pkg>`).
- **Wrapper noise breaks LSP.** A bun-installed binary here printed
  `Cannot detect the correct bin file ...` onto stdout, in-band with the
  protocol. Any wrapper that writes to stdout will corrupt the stream — a
  server that "connects but does nothing" is often this.
- **eslint comes from `vscode-langservers-extracted`**, which also provides the
  json, html and css servers if you want them later.
- **vue + typescript** are version-coupled; `vue-language-server` may need a
  matching `typescript-language-server`/`typescript`. If Vue files misbehave
  while plain TS is fine, suspect that pairing.
- **jdtls** wants a per-workspace data directory and is slow on first index.
- **Editing config by key name:** the PHP server's key here is `intelephense`,
  not `php`. Writing `.lsp.php.command` with jq silently creates a *new*,
  half-configured twelfth server instead of editing the existing one. After any
  jq edit, diff against the backup and re-count: `jq '.lsp|length'`.
