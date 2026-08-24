#!/usr/bin/env bash
# PostToolUseFailure hook for the LSP tool. A bare "no server for this file"
# says nothing about why, so this names the server that owns the extension,
# whether its binary is actually installed, and the command that fixes it.
# Silent whenever it has nothing useful to add.
set -u

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
path="$(printf '%s' "$payload" | jq -r '.tool_input.filePath // empty' 2>/dev/null)"
[ -n "$path" ] || exit 0

# Only the basename may carry the extension: a dot in a directory name
# (/srv/v1.2/Makefile) must not read as one. Test for the dot before
# lowercasing, or the comparison never matches.
base="${path##*/}"
case "$base" in
    *.*) ;;
    *) exit 0 ;;
esac
ext=".$(printf '%s' "${base##*.}" | tr '[:upper:]' '[:lower:]')"

lsp="${CLAUDE_PLUGIN_ROOT:-}/.lsp.json"
[ -f "$lsp" ] || exit 0

server="$(jq -r --arg e "$ext" '
    to_entries[] | select(.value.extensionToLanguage | has($e)) | .key' "$lsp" 2>/dev/null | head -1)"

if [ -z "$server" ]; then
    hint="nix-lsps declares no language server for \"$ext\" files, so this failure is
expected rather than a broken install. Servers it does cover:
$(jq -r '[to_entries[] | .value.extensionToLanguage | keys[]] | sort | join(" ")' "$lsp" 2>/dev/null)

To add one, put the extension in plugins/nix-lsps/.lsp.json under a server that can
handle it — no two servers may claim the same extension. Tell the user this in one
line; do not retry the same call."
else
    binary="$(jq -r --arg s "$server" '.[$s].command' "$lsp" 2>/dev/null)"
    if command -v "$binary" >/dev/null 2>&1; then
        # The server is installed, so this is some other failure. Adding a
        # misinstall story here would send the user down the wrong path.
        exit 0
    fi
    hint="nix-lsps: \"$ext\" is handled by $server, whose binary \"$binary\" is not on PATH.
That is why this call failed — the plugin declares servers but does not install them.

Fix, which the user must approve rather than have run for them:

    nix profile add github:Tschallacka/lsp-flake#lsps

Claude Code needs a restart afterwards, so the call will keep failing this session.
Say this in one line, do not retry, and point at
https://github.com/Tschallacka/lsp-flake/blob/main/LSP-SETUP.md for the detail."
fi

printf '%s' "$hint" | jq -Rs '{
    hookSpecificOutput: {
        hookEventName: "PostToolUseFailure",
        additionalContext: .
    }
}'
