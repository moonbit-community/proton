# Scripts

Small repository scripts used by generation workflows.

## `embed_asset.mjs`

Embeds a text file into generated MoonBit source.

```sh
node ./scripts/embed_asset.mjs <input> <output> <identifier>
```

## `e2e_bridge_smoke.mjs`

Runs native DLL bridge smoke scenarios through CEF remote debugging. Build and
assemble the active runtime first, then run:

```powershell
moon -C cli run . -- -C .. cef setup
$runtime = (Get-Content .proton\runtime.json | ConvertFrom-Json).dist
$env:PATH = (Resolve-Path "$runtime\bin").Path + ';' + $env:PATH
```

```sh
node ./scripts/e2e_bridge_smoke.mjs 38_async_extension_add 39_sync_async_extensions
node ./scripts/e2e_bridge_smoke.mjs 40_event_broadcast
node ./scripts/e2e_bridge_smoke.mjs 41_app_commands 42_attribute_codegen_commands 45_bridge_multi_window
```

The `e2e/` MoonBit module is part of `moon.work`. The script checks that
workspace membership before running the MoonBit e2e probe.
