# Proton

Proton is a MoonBit framework for building native desktop applications with a
web frontend.

Supported prebuilt runtimes:

- Windows x64
- macOS Apple Silicon
- Linux x64

## Quick start

Install the CLI and create a project:

```sh
moon install justjavac/proton_cli
proton_cli new my-app \
  --title "My App" \
  --identifier "com.example.my-app"
cd my-app
```

Set up the native runtime and start development:

```sh
proton_cli cef setup
proton_cli dev
```

The generated project contains a runnable `app/` package, an example command
extension, and a `moon.proton` configuration file. `.proton/` is a local
runtime cache and should not be committed.

## Application entry

Generated projects explicitly load `moon.proton` with `@proton.config(...)`:

```moonbit
fn main {
  @proton.run(() => {
    @proton.config("moon.proton")
    .extension(@counter.extension())
    .run_or_abort()
  })
}
```

The default config name honors `PROTON_CONFIG_PATH` (including
`proton_cli dev --config`) and resolves the packaged config location when the
application is bundled. Non-default paths are used exactly as provided.

For a small application, inline HTML can be opened directly:

```moonbit
fn main {
  @proton.run(() => {
    @proton.html(
      "Hello Proton",
      "<h1>Hello from MoonBit</h1>",
      width=900,
      height=700,
      debug=true,
    ).run_or_abort()
  })
}
```

The root package also supports URL, file, asset, and project-config entries
through `@proton.url`, `@proton.file`, `@proton.asset`, and `@proton.config`.

On macOS and Windows, web content can extend beneath the native titlebar while
retaining the system window controls:

```moonbit
window = {
  title: "My App",
  width: 900,
  height: 700,
  titlebar_style: "overlay",
}
```

`titlebar_style` accepts `"default"` and `"overlay"`. Overlay rendering is
implemented and shipped for macOS and Windows. Linux keeps the default
titlebar. On Windows, Proton consumes CEF's native draggable-region updates.
Set `-webkit-app-region: no-drag` on interactive descendants, then assign
`element.style.webkitAppRegion = "drag"` to the draggable container after it
exists in the DOM. The post-DOM assignment is required by the currently shipped
CEF build to emit its initial region update; later changes are reported directly
by CEF. These are CEF-provided regions, not an Electron compatibility shim.
Until the page reports its first region update, Proton keeps a small DPI-aware
leading drag fallback. Pages must also reserve the native caption-button area.
Overlay windows request DWM's dark caption appearance so the native controls
blend with dark application chrome.
Typed window configs send `titlebar_style` only when the loaded runtime reports
the `titlebar_overlay` feature. Older prebuilts and unsupported platforms omit
the field and retain their default titlebar behavior.
See `examples/48_titlebar_overlay` for a cross-platform overlay layout example.

Code-only apps can select the same style through the facade:

```moonbit
@proton.html("My App", html)
.titlebar_style(@proton.TitlebarStyle::Overlay)
```

## Frontend projects

Vite, Next, and similar tools can be configured in `moon.proton`:

```moonbit
frontend = {
  dev_url: "http://127.0.0.1:5173",
  dist: "frontend/dist",
  cwd: "frontend",
  before_dev: "npm run dev -- --host 127.0.0.1 --strictPort",
  before_build: "npm run build",
}
```

`proton_cli dev` runs `frontend.before_dev`, waits for `frontend.dev_url`, and
launches the app in development mode. `proton_cli build` runs
`frontend.before_build`, validates `frontend.dist`, and builds the MoonBit app
for the native target.

## Build

```sh
moon check --target native --diagnostic-limit 80
proton_cli build
proton_cli build -- --release
```

Arguments after `--` are passed to `moon build`; Proton always selects the
native target.

## Bundle and package

The `bundle` block in `moon.proton` enables package creation and selects its
default targets and output directory:

```moonbit
bundle = {
  active: true,
  targets: ["app", "zip"],
  output: "target/proton-dist",
}
```

Inspect the resolved bundle plan before creating artifacts:

```sh
proton_cli package app --dry-run
proton_cli package app
```

The package command performs a release build unless `--no-build` is supplied.
Package output is written to `target/proton-dist` by default. Icons, resources,
output targets, signing, and notarization are configured through `moon.proton`
and package command options.

## Diagnose a project

```sh
proton_cli doctor
proton_cli doctor --deep
proton_cli doctor --frontend
```

Run `proton_cli cef setup` again when the active runtime is missing or invalid.
Use `PROTON_CEF_LOG=default` temporarily when browser-runtime logs are needed.

See [examples/Readme.md](examples/Readme.md) for runnable examples. Repository
contributors and release maintainers should follow [AGENTS.md](AGENTS.md).

## License

Apache License 2.0. See [LICENSE.md](LICENSE.md).
