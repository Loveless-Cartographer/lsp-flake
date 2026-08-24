# lsp-flake

Eleven language servers as a single Nix flake, wired into [opencode](https://opencode.ai)
by a generator and into [Claude Code](#claude-code) by a plugin in this repo.

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

## Claude Code

Claude Code has a built-in LSP layer, but no `settings.json` key for it — language
servers are registered by **plugins**. This repo is a marketplace with one plugin,
`nix-lsps`, declaring all ten servers at once.

```sh
claude plugin marketplace add Tschallacka/lsp-flake
claude plugin install nix-lsps@lsp-flake
```

Restart Claude Code afterwards. `/lsp-doctor` then tells you which servers are
actually present.

### Verifying it works

Ask Claude to use its `LSP` tool on a file. On a `.phtml` template holding a
`Greeter` class, the three operations that matter all resolve through
`intelephense`:

| Operation | Result |
| --- | --- |
| `documentSymbol` | the real structure — `Greeter` (Class), `$name` (Property, private), `__construct` (Constructor), `greet` (Method) |
| `hover` on a `greet()` call | `Greeter::greet`, `public function greet(): string`, `@return string` |
| `goToDefinition` on the same call | the method declaration, `template.phtml:12:21` |

Symbol kinds and PHP visibility come back correctly, so this is the language
server parsing the file, not a text outline.

One trap if you go looking for this yourself: **`claude -p` does not appear to
start the LSP layer.** A non-interactive run reports no diagnostics and logs
nothing LSP-related under `--debug`, even with the plugin installed and working.
Test in an interactive session, or through the `LSP` tool directly.

### Requirements, and what happens without them

The plugin declares servers; it cannot install them. Each `command` is a bare
binary name resolved on `PATH`, so the binaries have to exist — which is what the
flake above is for:

```sh
nix profile add github:Tschallacka/lsp-flake#lsps
```

If you do not have Nix, install it first — a single command, documented at
<https://nixos.org/download/>:

```sh
sh <(curl -L https://nixos.org/nix/install) --daemon
```

**Missing binaries degrade quietly rather than breaking the session.** Servers
start lazily, when a file of a matching extension is first opened, so a server
whose binary is absent costs you intelligence for that one language and nothing
else. Run `/lsp-doctor` to see which are missing and what to install; use
`claude --debug` if you want the startup failure itself.

There is **no install-time trigger** in the plugin system — no hook fires when a
plugin is installed, so the plugin cannot run `nix profile add` for you. The two
steps are genuinely separate: install the binaries, install the plugin.

### Extensions, including `.phtml`

Each server maps extensions to LSP language ids itself, so the mapping is
editable in one place — `plugins/nix-lsps/.lsp.json`. This is the reason the
plugin exists rather than using the official per-language ones: Anthropic's
`php-lsp` maps `.php` only, which leaves Magento and WordPress templates dark.
`nix-lsps` maps `.phtml`, `.module` and `.inc` to PHP as well, plus `.zsh`/`.ksh`
to shell, `.mts`/`.cts` to TypeScript and `.pyw` to Python.

To add your own, add the extension to that file — no two servers may claim the
same extension.

### Conflicts with the official LSP plugins

The official marketplace ships `php-lsp`, `pyright-lsp`, `typescript-lsp`,
`rust-analyzer-lsp`, `jdtls-lsp`, `kotlin-lsp` and more. `nix-lsps` **replaces**
those — do not enable both for the same language. Two plugins declaring a server
for one extension is a conflict, not a merge.

`eslint` is deliberately absent: `vscode-eslint-language-server` wants the same
`.js`/`.ts` extensions as `typescript-language-server`, and only one server may
own an extension. It is in the flake, and configured for opencode, which has no
such restriction.

### Editors other than opencode

The flake is just binaries on `PATH`, so anything that discovers language
servers there works. Only the generator is opencode-specific.

For Claude Code, see [Claude Code](#claude-code) above — it needs the plugin in
this repo, not a config key.

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
- Of the ten servers the plugin declares, only `intelephense` has been exercised
  end to end in Claude Code. The other nine are declared the same way and start
  the same way, but their intelligence is unverified here.

## License

MIT — see [LICENSE](LICENSE).
