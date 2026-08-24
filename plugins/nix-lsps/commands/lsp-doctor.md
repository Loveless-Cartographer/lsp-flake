---
description: Check which of the nix-lsps language servers are actually installed
---

Run this exact script and report the result to the user:

```sh
missing=0
printf '%-32s %s\n' SERVER STATUS
while IFS=: read -r bin lang; do
    [ -n "$bin" ] || continue
    if command -v "$bin" >/dev/null 2>&1; then
        printf '%-32s ok  (%s)\n' "$bin" "$(command -v "$bin")"
    else
        printf '%-32s MISSING\n' "$bin"
        missing=$((missing + 1))
    fi
done <<'SERVERS'
bash-language-server:shell
intelephense:php
jdtls:java
kotlin-language-server:kotlin
nixd:nix
pyright-langserver:python
rust-analyzer:rust
typescript-language-server:typescript
vue-language-server:vue
yaml-language-server:yaml
SERVERS
printf '\n%d of 10 missing\n' "$missing"
```

Then:

- If nothing is missing, say so in one line and stop.
- If some are missing, explain that those languages simply have no LSP support in
  this session — the rest still work, nothing is broken — and give the fix:

      nix profile add github:Tschallacka/lsp-flake#lsps

  If `nix` itself is not on PATH, point them at https://nixos.org/download/
  first; the plugin cannot install anything on its own.

Do not attempt to install anything yourself unless the user asks.
