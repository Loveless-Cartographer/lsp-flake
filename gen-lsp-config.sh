#!/usr/bin/env bash
# Generates the opencode `lsp` block for the servers in $BIN and merges it
# into ~/.config/opencode/opencode.json, preserving every other key.
set -euo pipefail

BIN="${BIN:-$HOME/.nix-profile/bin}"
CONFIG="${CONFIG:-$HOME/.config/opencode/opencode.json}"

# name : binary : args : extensions
servers='
bash:bash-language-server:start:.sh .bash .zsh
eslint:vscode-eslint-language-server:--stdio:.js .jsx .ts .tsx .vue .mjs .cjs
jdtls:jdtls::.java
kotlin:kotlin-language-server::.kt .kts
nixd:nixd::.nix
intelephense:intelephense:--stdio:.php .phtml
pyright:pyright-langserver:--stdio:.py .pyi
rust:rust-analyzer::.rs
typescript:typescript-language-server:--stdio:.ts .tsx .js .jsx .mjs .cjs
vue:vue-language-server:--stdio:.vue
yaml:yaml-language-server:--stdio:.yaml .yml
'

block='{}'
missing=0
while IFS=: read -r name bin args exts; do
    [ -n "$name" ] || continue
    path="$BIN/$bin"
    if [ ! -x "$path" ]; then
        printf 'missing: %s (%s)\n' "$name" "$path" >&2
        missing=$((missing + 1))
        continue
    fi
    block="$(printf '%s' "$block" | jq \
        --arg name "$name" --arg path "$path" --arg args "$args" --arg exts "$exts" \
        '.[$name] = {
            command: ([$path] + ($args | split(" ") | map(select(length > 0)))),
            extensions: ($exts | split(" ") | map(select(length > 0)))
         }')"
done <<SERVERS
$servers
SERVERS

[ "$missing" -eq 0 ] || { printf '%d server(s) not found under %s; install them first\n' "$missing" "$BIN" >&2; exit 69; }

mkdir -p "$(dirname "$CONFIG")"
[ -f "$CONFIG" ] || printf '{}\n' > "$CONFIG"
jq -e . "$CONFIG" >/dev/null || { printf '%s is not valid JSON; fix or move it first\n' "$CONFIG" >&2; exit 65; }

cp "$CONFIG" "$CONFIG.bak-$(date +%Y%m%dT%H%M%S)"
tmp="$(mktemp)"
jq --argjson lsp "$block" '.lsp = $lsp' "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
printf 'wrote %d servers to %s\n' "$(printf '%s' "$block" | jq 'length')" "$CONFIG"
