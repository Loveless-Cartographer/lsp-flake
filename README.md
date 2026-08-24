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
plugin is installed, and the manifest has no post-install message field, so the
plugin cannot run `nix profile add` for you.

What it does instead is check at **session start**, and it leads with the fix rather
than an explanation: the missing servers and the one command that installs them. It
also tells the agent to raise it in one line beside whatever the user actually asked
for, so a session opened for other work is not derailed by a tooling pitch. If
Nix itself is absent it adds the second command and a link, and keeps the "what is
Nix, and why not a container" background one line long, to be expanded only if the
user asks.

It reports a given situation **once**, and only after the note was actually written out — a failed emission is retried at the next session start rather than suppressed forever. A stamp under
`${XDG_STATE_HOME:-~/.local/state}/nix-lsps` records which servers were missing and
whether Nix was present; an identical situation stays silent at every later session
start, and the note returns only when that changes — a server disappears, or Nix
arrives and the remaining step is the flake. Someone who has decided not to install
anything is told once, not at every startup.

The check is `plugins/nix-lsps/hooks/check-lsp-servers.sh`; it needs only a shell,
and uses `jq` for structured output when available. `NIX_LSPS_PREVIEW=missing` or
`=no-nix` previews either note without uninstalling anything, bypassing the stamp.

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

## More detail

[`LSP-SETUP.md`](LSP-SETUP.md) is the long form — prerequisites, the flake in
full, install and verification, the opencode and Claude Code wiring, and a
gotchas list covering PATH shadowing, wrapper output corrupting the protocol
stream, and the rustup shim that intercepts `rust-analyzer`.

## Caveats

- Built and used on `x86_64-linux`. The flake declares `aarch64-linux`,
  `x86_64-darwin` and `aarch64-darwin` too.
- nixpkgs `intelephense` runs a little behind the npm release.
- `nix profile upgrade lsps` moves all eleven together. Holding one server back
  means editing the flake.

## License

MIT — see [LICENSE](LICENSE).
