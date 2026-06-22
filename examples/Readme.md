# Examples

Run commands from the repository root.

Generated-command examples use the released Proton CLI. Install it into the
tool directory used by `examples/moon.mod`:

```sh
moon install justjavac/proton_cli --bin target/proton-tools
```

Build all examples:

```sh
moon -C examples build --target native
```

Run one example:

```sh
moon -C examples run 19_app_fs --target native
```

CEF examples need the local CEF runtime and helper process:

```sh
target/proton-tools/proton_cli cef setup
moon -C proton build cef_process --target native
moon -C examples run 43_cef_bind_smoke --target native
```

Run automated CEF smoke scenarios:

```sh
node ./scripts/e2e_cdp_smoke.mjs
```

## Groups

- `01_*` through `15_*`: low-level `webview` examples
- `17_*` and `18_*`: direct extension installation through `core`
- `19_*` through `35_*`: app-style startup through `justjavac/proton`
- `37_*` and `43_*`: CEF backend smoke examples
- `38_*` through `42_*`: command extensions and generated command bridges
- `44_project_config`: `moon.proton` project config decoding

App examples declare extensions in MoonBit code. `moon.proton` configures app
settings such as window, entry, debug, frontend, and bundle metadata.
