#!/usr/bin/env bash
# SessionStart hook: tell the agent to walk the user through installing the
# language servers, but only when something is actually missing. Silent
# otherwise — a working setup must cost nothing.
set -u

# NIX_LSPS_PREVIEW lets you see the note without uninstalling anything:
#   missing  — pretend every server is absent, Nix present
#   no-nix   — pretend Nix is absent too
# Unset (the normal case) means a real check.
preview="${NIX_LSPS_PREVIEW:-}"

servers="bash-language-server intelephense jdtls kotlin-language-server nixd
pyright-langserver rust-analyzer typescript-language-server vue-language-server
yaml-language-server"

missing=""
present=0
for b in $servers; do
    if [ -z "$preview" ] && command -v "$b" >/dev/null 2>&1; then
        present=$((present + 1))
    else
        missing="$missing $b"
    fi
done

# Everything present: say nothing at all.
[ -z "$missing" ] && exit 0

if [ "$preview" != "no-nix" ] && command -v nix >/dev/null 2>&1; then
    note="nix-lsps: $((10 - present)) of 10 language servers are not on PATH:$missing

Tell the user, and offer to run this (do not run it unasked):

    nix profile add github:Tschallacka/lsp-flake#lsps

Claude Code needs a restart afterwards."
else
    note="nix-lsps: no language server can start. Nix is not on PATH, and the servers ship as a Nix flake.

Tell the user, and offer these two steps (do not run either unasked):

    sh <(curl -L https://nixos.org/nix/install) --daemon    # needs sudo, asks its own questions — better run by hand
    nix profile add github:Tschallacka/lsp-flake#lsps

Claude Code needs a restart afterwards. Docs: https://nixos.org/download/

Background, only if they ask: Nix is a package manager that installs each package into its own immutable directory and puts real binaries on PATH, pinned by a lockfile — unlike a container, there is no daemon or volume mount, so an editor can execute them directly. It is used here because these servers come from four ecosystems (npm, JDK, Rust, PHP), and the flake makes them one dependency."
fi

# Report a given situation once. The key covers Nix's presence and exactly which
# servers are missing, so the note returns if that changes (a server removed, Nix
# installed) but a user who has decided not to install anything is not nagged at
# every session start. A preview always prints.
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/nix-lsps"
key="$(command -v nix >/dev/null 2>&1 && printf 'nix'; printf '%s' "$missing")"
key="$(printf '%s' "$key" | cksum)"
if [ -z "$preview" ]; then
    if [ -f "$state_dir/reported" ] && [ "$(cat "$state_dir/reported" 2>/dev/null)" = "$key" ]; then
        exit 0
    fi
fi

# SessionStart contract: additionalContext is injected into the session. jq is
# not a dependency of this plugin, so fall back to plain stdout, which
# SessionStart also accepts as context.
emitted=0
if command -v jq >/dev/null 2>&1; then
    printf '%s' "$note" | jq -Rs '{
        hookSpecificOutput: {
            hookEventName: "SessionStart",
            additionalContext: .
        }
    }' && emitted=1
else
    printf '%s\n' "$note" && emitted=1
fi

# Only now that the note has actually been emitted is the situation "reported".
# Stamping earlier would let a killed or timed-out hook suppress a note nobody
# ever saw.
if [ -z "$preview" ] && [ "$emitted" -eq 1 ]; then
    mkdir -p "$state_dir" 2>/dev/null && printf '%s\n' "$key" > "$state_dir/reported" 2>/dev/null || true
fi
