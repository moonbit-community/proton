# Scripts

Small repository scripts used by build and smoke-test workflows.

## `embed_asset.mjs`

Embeds a text file into generated MoonBit source.

```sh
node ./scripts/embed_asset.mjs <input> <output> <identifier>
```

## `setup_cef.mjs`

Installs the Windows CEF runtime into `.cef-cache/`.

```powershell
node .\scripts\setup_cef.mjs
```

## `e2e_cdp_smoke.mjs`

Builds the CEF helper, starts selected examples, and runs CDP-based smoke
probes.

```powershell
node .\scripts\e2e_cdp_smoke.mjs
node .\scripts\e2e_cdp_smoke.mjs 38_async_extension_add 41_app_commands
```
