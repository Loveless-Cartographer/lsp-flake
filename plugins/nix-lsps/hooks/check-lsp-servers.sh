#!/usr/bin/env bash
# SessionStart hook: tell the agent to walk the user through installing the
# language servers, but only when something is actually missing. Silent
# otherwise — a working setup must cost nothing.
set -u

servers="bash-language-server intelephense jdtls kotlin-language-server nixd
pyright-langserver rust-analyzer typescript-language-server vue-language-server
yaml-language-server"

missing=""
present=0
for b in $servers; do
    if command -v "$b" >/dev/null 2>&1; then
        present=$((present + 1))
    else
        missing="$missing $b"
    fi
done

# Everything present: say nothing at all.
[ -z "$missing" ] && exit 0

if command -v nix >/dev/null 2>&1; then
    note="The nix-lsps plugin is installed, but $((10 - present)) of its 10 language servers are not on PATH:$missing

Nix IS installed, so tell the user this and offer to run it for them:

    nix profile add github:Tschallacka/lsp-flake#lsps

That installs all eleven servers as one unit. Mention that a restart of Claude Code is needed afterwards. Do not run it without asking."
else
    note="The nix-lsps plugin is installed, but none of its language servers can work: Nix itself is not on PATH, and the servers are distributed as a Nix flake.

Explain this to the user, briefly:

- Nix is a package manager. It installs each package into its own immutable directory and links what you asked for into your profile, so versions never collide and an install is exactly reproducible from a lockfile.
- Compared with Docker: Docker isolates a whole running environment in a container, which is why the tools inside it are awkward to use as your own commands. Nix installs real binaries onto your PATH — an editor or Claude Code can execute them directly — while still pinning versions. No daemon, no container, no volume mounts.
- Why it is needed here: these are eleven language servers from four ecosystems (npm, JDK, Rust, PHP). Installing them by hand means four package managers and eleven version pins. The flake makes them one dependency that installs, upgrades and removes together.

Then offer the two steps, and do not run either without asking:

    sh <(curl -L https://nixos.org/nix/install) --daemon
    nix profile add github:Tschallacka/lsp-flake#lsps

The installer needs sudo and asks its own questions, so the user is better off running it themselves in a terminal; https://nixos.org/download/ documents it. Mention that Claude Code needs a restart afterwards."
fi

# SessionStart contract: additionalContext is injected into the session. jq is
# not a dependency of this plugin, so fall back to plain stdout, which
# SessionStart also accepts as context.
if command -v jq >/dev/null 2>&1; then
    printf '%s' "$note" | jq -Rs '{
        hookSpecificOutput: {
            hookEventName: "SessionStart",
            additionalContext: .
        }
    }'
else
    printf '%s\n' "$note"
fi
