# lsp-flake

Eleven language servers as a single Nix flake, plus a generator that wires them
into [opencode](https://opencode.ai).

One `nix profile add` gets you bash, eslint, Java, Kotlin, Nix, PHP, Python,
Rust, TypeScript, Vue and YAML intelligence — and one `nix profile upgrade`
moves the whole set. The point is that they install, upgrade and remove as a
unit instead of eleven separately-drifting packages.

## What's in it

| Server | Package | Handles |
| --- | --- | --- |
| `bash-language-server` | `bash-language-server` | `.sh` `.bash` `.zsh` |
| `vscode-eslint-language-server` | `vscode-langservers-extracted` | `.js` `.jsx` `.ts` `.tsx` `.vue` `.mjs` `.cjs` |
| `jdtls` | `jdt-language-server` | `.java` |
| `kotlin-language-server` | `kotlin-language-server` | `.kt` `.kts` |
| `nixd` | `nixd` | `.nix` |
| `intelephense` | `intelephense` | `.php` `.phtml` |
| `pyright-langserver` | `pyright` | `.py` `.pyi` |
| `rust-analyzer` | `rust-analyzer` | `.rs` |
| `typescript-language-server` | `typescript-language-server` | `.ts` `.tsx` `.js` `.jsx` `.mjs` `.cjs` |
| `vue-language-server` | `vue-language-server` | `.vue` |
| `yaml-language-server` | `yaml-language-server` | `.yaml` `.yml` |

`vscode-langservers-extracted` also ships json, html and css servers if you want
to add them to the config later.

## Use it

Requires Nix with flakes enabled, `jq`, and roughly 2.5 GB of store space —
`jdt-language-server` brings its own JDK.

```sh
nix build --no-link --print-out-paths github:Tschallacka/lsp-flake#lsps
nix profile add github:Tschallacka/lsp-flake#lsps
```

Or clone it and treat the flake as yours to edit — that's the expected mode, since
which eleven servers you want is a personal question.

There's also a dev shell, if you'd rather not touch your profile:

```sh
nix develop github:Tschallacka/lsp-flake
```

### Wire it into opencode

```sh
./gen-lsp-config.sh
```

Writes the `lsp` block of `~/.config/opencode/opencode.json` and leaves every
other key alone. It backs the file up first, refuses to run if the existing
config isn't valid JSON, and exits 69 rather than writing a half-configuration
if any binary is missing. Set `BIN=` to point at somewhere other than
`~/.nix-profile/bin`.

To add a server: add the package to `paths` in `flake.nix`, add a row to the
`servers` table in `gen-lsp-config.sh`, rebuild, rerun the generator.

### Editors other than opencode

The flake is just binaries on `PATH`, so anything that discovers language
servers there works. Only the generator is opencode-specific.

Note that **Claude Code has no user-facing setting for language servers.** It
has an internal LSP layer, but no config key to register these with, so
installing them doesn't wire them into it.

## Why `allowUnfree` is in the flake

`intelephense` is unfree. The flake imports nixpkgs with
`config.allowUnfree = true` inside its own scope, so no `NIXPKGS_ALLOW_UNFREE=1`
and no `--impure` is needed — and the permission doesn't leak into anything else
you build on the machine. If you'd rather not have an unfree package at all,
drop `intelephense` from `paths` and the `intelephense` row from the generator.

## Testing a language server

Don't use `--version`. `intelephense --version` isn't a supported flag and
prints its entire bundled JavaScript. Hand it an LSP `initialize` instead:

```sh
body='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{}}}'
{ printf 'Content-Length: %d\r\n\r\n%s' "${#body}" "$body"; sleep 6; } \
  | timeout 20 intelephense --stdio 2>&1 | head -c 200
```

A healthy server replies with `Content-Length:` framing and JSON-RPC. The
`sleep` matters: without it stdin closes and the server exits before answering,
which looks exactly like a broken binary.

[`LSP-SETUP.md`](LSP-SETUP.md) has the full walkthrough and a longer list of
things that cost time to work out — PATH shadowing by npm/bun/cargo copies,
wrapper output corrupting the protocol stream, and the rustup shim that
intercepts `rust-analyzer`.

## Caveats

- Verified on `x86_64-linux`. The flake declares `aarch64-linux`,
  `x86_64-darwin` and `aarch64-darwin`; those are untested.
- nixpkgs `intelephense` runs a little behind the npm release.
- `nix profile upgrade lsps` moves all eleven together. Holding one server back
  means editing the flake.

## License

MIT — see [LICENSE](LICENSE).
