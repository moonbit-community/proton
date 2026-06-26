# Scripts

Small repository scripts used by generation workflows.

## `embed_asset.mjs`

Embeds a text file into generated MoonBit source.

```sh
node ./scripts/embed_asset.mjs <input> <output> <identifier>
```

## `e2e_bridge_smoke.mjs`

Runs native DLL bridge smoke scenarios through CEF remote debugging. Build and
install `native/dist` first, then run:

```sh
node ./scripts/e2e_bridge_smoke.mjs 38_async_extension_add 39_sync_async_extensions
node ./scripts/e2e_bridge_smoke.mjs 40_event_broadcast
node ./scripts/e2e_bridge_smoke.mjs 41_app_commands 42_attribute_codegen_commands 45_bridge_multi_window
```

If an `e2e/` MoonBit module is present, the script first runs
`moon work use ./e2e` because that module is not assumed to be listed in
`moon.work`.
