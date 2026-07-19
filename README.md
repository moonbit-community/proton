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

Generated projects load `moon.proton` with `@proton.app()`:

```moonbit
async fn main {
  @proton.app()
  .extension(@counter.extension())
  .run_or_abort()
}
```

For a small application, inline HTML can be opened directly:

```moonbit
async fn main {
  @proton.html(
    "Hello Proton",
    "<h1>Hello from MoonBit</h1>",
    width=900,
    height=700,
    debug=true,
  ).run_or_abort()
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
titlebar. On Windows, Proton reserves a fixed native drag handle at the leading
edge of the caption band. Its width follows the live system caption-button
width, with the current-DPI metric as a fallback; the rest of the titlebar
remains available to web controls. Web content placed over the leading handle
does not receive mouse input, so pages should use it for an app icon or other
drag-only chrome and must also reserve
the native caption-button area. Overlay windows request DWM's dark caption
appearance so the native controls blend with dark application chrome. This
setting does not implement
`-webkit-app-region` or another HTML drag-region API.
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

`proton_cli dev` starts the frontend development server and launches the app.
The build and package commands use the generated files from `frontend.dist`.

## Build and package

```sh
moon check --target native --diagnostic-limit 80
proton_cli build
proton_cli package app --dry-run
proton_cli package app
```

Package output is written to `target/proton-dist` by default. Icons, resources,
output targets, signing, and notarization are configured through `moon.proton`
and the package command options.

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
