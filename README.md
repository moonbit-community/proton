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

`size_hint` accepts `"none"`, `"fixed"`, `"min"`, and `"max"`. A fixed window
cannot be resized; minimum and maximum hints constrain resizing relative to the
configured width and height.

Code-only apps can select the same style through the facade:

```moonbit
@proton.html("My App", html)
.titlebar_style(@proton.TitlebarStyle::Overlay)
```

The typed facade can own additional windows without replacing Proton's bridge
pump:

```moonbit
@proton.html("Main", main_html)
.add_window(
  "details",
  "Details",
  @proton.AppEntry::Html(details_html),
  width=640,
  height=480,
)
```

Each window has a stable id. The process remains active until every window has
closed. See `examples/45_bridge_multi_window`.

On macOS, packaged URL and file activations are delivered through a typed app
handler:

```moonbit
@proton.config("moon.proton")
.on_launch_input(async fn(input) noraise {
  match input {
    OpenUrls(urls) => ...
    OpenFiles(paths) => ...
    Reopen => ...
  }
})
```

Use `@proton.app_data_dir("com.example.my-app")` to resolve the stable native
data directory for an application identifier. The function does not create the
directory.

## Headless automation

Code-driven applications can run with CEF off-screen rendering and no native
top-level window:

```moonbit
@proton.config("moon.proton")
.headless()
.run_or_abort()
```

Set `PROTON_HEADLESS=1` to force the same mode in automated runs without
changing application code. Headless mode is independent of remote debugging,
so CDP can be enabled separately for end-to-end tests. Native menus, dialogs,
and titlebar overlay are unavailable in this mode. Linux still requires an
X11 display; use Xvfb in display-less CI jobs.

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

## E2E tests

The native bridge E2E suite is implemented in MoonBit and owns its application
processes, CDP connections, frontend servers, and cleanup:

```sh
PROTON_NATIVE_DIST="$PWD/native/dist" \
PATH="$PWD/native/dist/bin:$PATH" \
moon -C e2e test -p justjavac/proton/e2e/test \
  --target native --no-parallelize --diagnostic-limit 200
```

For an application that is already running with CDP enabled, use the typed
driver instead:

```sh
MBT_PROTON_E2E_SCENARIO=41_app_commands \
MBT_CDP_TARGET=9222 moon -C e2e run test --target native
```

## Bundle and package

The `bundle` block in `moon.proton` enables package creation and selects its
default targets and output directory:

```moonbit
bundle = {
  active: true,
  targets: ["app", "zip"],
  url_schemes: ["my-app"],
  document_types: [
    {
      name: "Text document",
      extensions: ["txt", "md"],
      role: "Editor",
    },
  ],
  output: "target/proton-dist",
}
```

Inspect the resolved bundle plan before creating artifacts:

```sh
proton_cli package --dry-run
proton_cli package
```

The package command performs a release build unless `--no-build` is supplied.
Package output is written to `target/proton-dist` by default. Icons, resources,
output targets, signing, notarization, custom URL schemes, and macOS document
types are configured through `moon.proton` and package command options.

The `dmg` target is available on macOS. It creates a compressed disk image
containing the app and an `/Applications` shortcut for drag-to-install:

```sh
proton_cli package --target app --target dmg
```

With `--notarize`, Proton submits the DMG when that target is enabled, then
staples and validates both the DMG and the app before creating any requested
ZIP archive. Without a `dmg` target, the existing app notarization flow is
used. Windows supports the `app` and `zip` targets.

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
