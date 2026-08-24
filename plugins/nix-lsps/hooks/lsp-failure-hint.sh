#!/usr/bin/env bash
# PostToolUse (and PostToolUseFailure) hook for the LSP tool. A bare "No LSP
# server available for file type .rb" says nothing about why, so this names the
# server that owns the extension, whether its binary is actually installed, and
# the command that fixes it. Silent whenever it has nothing useful to add.
#
# PostToolUse, not only PostToolUseFailure: the LSP tool RETURNS that message as
# an ordinary result rather than throwing, so the failure event never fires for
# it. Verified by a fresh session — the call produced the bare message and no
# hook context at all. PostToolUseFailure stays declared for a genuine crash.
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

# No response gate. An earlier version only spoke when the response matched a list
# of failure strings, and missed the case that matters most: a missing binary fails
# with "Command failed with ENOENT ... Executable not found in $PATH", which was on
# no list. Decide from the declaration instead — it cannot go stale:
#
#   extension no server claims  -> the call cannot have succeeded, so explain
#   extension claimed, binary present -> silent; the failure is something else
#   extension claimed, binary absent  -> the call cannot have succeeded, so explain
#
# That is immune to how the harness happens to word an error.

lsp="${CLAUDE_PLUGIN_ROOT:-}/.lsp.json"
[ -f "$lsp" ] || exit 0

server="$(jq -r --arg e "$ext" '
    to_entries[] | select(.value.extensionToLanguage | has($e)) | .key' "$lsp" 2>/dev/null | head -1)"

if [ -z "$server" ]; then
    hint="nix-lsps declares no language server for \"$ext\" files, so this failure is
expected rather than a broken install. Servers it does cover:
$(jq -r '[to_entries[] | .value.extensionToLanguage | keys[]] | sort | join(" ")' "$lsp" 2>/dev/null)

Adding one means editing this plugin's .lsp.json — but the installed copy lives in a
read-only cache, so it has to be changed at the source and reinstalled:
https://github.com/Tschallacka/lsp-flake/blob/main/plugins/nix-lsps/.lsp.json
No two servers may claim the same extension. Tell the user this in one line; do not
retry the same call."
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

# Echo back whichever event actually invoked us; the field must match or the
# output is rejected.
event="$(printf '%s' "$payload" | jq -r '.hook_event_name // "PostToolUse"' 2>/dev/null)"
printf '%s' "$hint" | jq -Rs --arg event "$event" '{
    hookSpecificOutput: {
        hookEventName: $event,
        additionalContext: .
    }
}'
