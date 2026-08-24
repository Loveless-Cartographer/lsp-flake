# nix-lsps

Ten language servers registered with Claude Code: bash, PHP (including `.phtml`),
Java, Kotlin, Nix, Python, Rust, TypeScript, Vue, YAML.

## This plugin does not install the servers

It declares them. The binaries have to exist on `PATH` or **nothing happens** — no
error, just no code intelligence. They come from the Nix flake in the same repo:

```sh
nix profile add github:Tschallacka/lsp-flake#lsps
```

Then restart Claude Code. `/lsp-doctor` reports which servers are actually present.

If `nix` itself is missing, install it first — one command, needing sudo and asking
its own questions, so run it by hand:

```sh
sh <(curl -L https://nixos.org/nix/install) --daemon
```

Full walkthrough and gotchas: [LSP-SETUP.md](../../LSP-SETUP.md).

## Installing this for someone

Two steps, not one. Installing the plugin alone leaves them with no language
intelligence and no error message. Do both, or tell them the second step is
outstanding:

1. `nix profile add github:Tschallacka/lsp-flake#lsps` — the binaries
2. `claude plugin install nix-lsps@lsp-flake` — this plugin

A session-start check reports any missing servers, but only from the **next**
session onward — it cannot warn during the session that installed the plugin.
Run `/lsp-doctor` instead of waiting for it.

## When a call fails

`PostToolUseFailure` on the `LSP` tool names the server that owns the extension, says
whether its binary is missing, and gives the install command — instead of a bare "no
server for this file". Silent when the server is present, since the failure is then
something else.

## Notes

- `.phtml`, `.module` and `.inc` map to PHP. Anthropic's official `php-lsp` maps
  `.php` only, which is the main reason to prefer this plugin.
- It **replaces** the official per-language LSP plugins (`php-lsp`, `pyright-lsp`,
  `typescript-lsp`, `rust-analyzer-lsp`, `jdtls-lsp`, `kotlin-lsp`). Do not enable
  both for one language — two plugins declaring a server for one extension is a
  conflict, not a merge.
- `eslint` is absent by design: it wants the same `.js`/`.ts` extensions as
  `typescript-language-server`, and only one server may own an extension.
- Extension-to-language mapping lives in `.lsp.json`, editable in one place.

MIT — see [LICENSE](../../LICENSE).
