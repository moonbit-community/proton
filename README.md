# Proton

Proton is a MoonBit framework for building native desktop applications with a
web frontend.

Supported source-built native backends:

- Windows x64
- macOS Apple Silicon
- Linux x64

## Quick start

Install the CLI and create a project:

```sh
moon install moonbit-community/proton_cli
proton_cli new my-app --template minimal --yes
cd my-app
```

Choose `minimal` for a single-module app with inline HTML, or `isomorphic` for
the three-module Rabbita and Warren Todo example. Without `--template`, `new`
uses `isomorphic` by default.

Fetch the MoonBit dependencies and set up the native runtime:

```sh
moon update
proton_cli cef setup
```

Start development:

```sh
proton_cli dev
```

The minimal project runs directly from `app/main.mbt` without a separate
frontend toolchain.

`cef setup` installs the exact CEF SDK and runtime required by this Proton
release into the user-wide immutable store at `~/.proton/store`. It also
installs the release's CEF subprocess helper once under
`~/.proton/helpers/<platform>/<version>`. Every project using the same Proton
release resolves these installations directly; projects contain no runtime or
helper copy and no runtime-selection file. Proton's native sources are compiled
into the application by Moon, while only CEF remains an external runtime. Set
`PROTON_RUNTIME_STORE` to an absolute path to relocate the CEF store.

`proton_cli`, `proton`, `proton_package`, and `proton_cefsetup` are released in
lockstep. The CLI resolves the runtime and helper installed by setup; it does
not inspect a project's Moon workspace or dependency source directories.
`proton_cli cef requirements` prints the active requirement as JSON.

## Application entry

Both templates define application runtime behavior with the MoonBit `App`
builder. The `isomorphic` template also registers typed commands in
`backend/app/main.mbt`:

```moonbit
async fn main {
  let backend = @todo.Backend()
  @proton.asset("My App", "frontend/dist/index.html")
  .load_config()
  .single_instance()
  .commands(fn(registrar) raise { backend.register_commands(registrar) })
  .run_or_abort()
}
```

Commands are declared once in the `shared/` contract package and wired into
the runtime with `.commands(...)`; the frontend invokes them through the
typed Rabbita client and can subscribe to events pushed by the backend.

For a small application, inline HTML can be opened directly:

```moonbit
async fn main {
  @proton.html(
    "Hello Proton",
    "<h1>Hello from MoonBit</h1>",
    width=900,
    height=700,
    debug=true,
  ).load_config().run_or_abort()
}
```

The root package also supports URL, file, and packaged asset entries through
`@proton.url`, `@proton.file`, and `@proton.asset`.

## Renderer capabilities

Commands registered with `.commands(...)` are available to the primary
window's configured entry by default. Use `targets` when another window or
Proton's bundled origin also needs them.

Extensions expose typed capabilities. Adding a capability both installs its
backend handlers and grants it to the selected renderer, so registration and
authority cannot drift apart. Filesystem access additionally declares path
ranges and exact commands:

```moonbit
@proton.html("Files", html)
.capability(
  @fs.capability([
    @fs.PermissionRoot("./workspace", [
      "read_file",
      "write_file",
      "readdir",
    ]),
  ]),
)
```

The default target is `@proton.RendererTarget::entry()` for the primary
window. Multi-window applications pass `targets=[...]` with
`RendererTarget::entry(window=...)` or `RendererTarget::bundled(window=...)`.
Omitting a capability is valid; attempts to invoke an unavailable operation are
rejected by the bridge rather than preventing the application from starting.

The renderer cannot select or widen these roots. Proton matches the trusted
frame origin in native code, rechecks the grant during MoonBit dispatch, and
the filesystem extension validates the canonical target before each operation.
Relative filesystem roots and request paths are anchored to
`@proton.resource_dir()`: the project root supplied by `proton_cli dev`, the
packaged resources directory, or the startup working directory for direct runs.

On macOS and Windows, web content can extend beneath the native titlebar while
retaining the system window controls:

```moonbit
@proton.html("My App", html)
.titlebar_style(@proton.TitlebarStyle::Overlay)
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
Typed window configs send `titlebar_style` only when the source-built backend
reports the `titlebar_overlay` feature. Unsupported platforms retain their
default titlebar behavior.
See `examples/48_titlebar_overlay` for a cross-platform overlay layout example.

The primary entry constructors accept `resizable=false` for a fixed window.
Secondary windows can select `WindowSizeHint::Unconstrained`, `Fixed`, `Min`,
or `Max`; minimum and maximum hints constrain resizing relative to the
configured width and height. A running `WindowHandle` can also update those
constraints with `set_minimum_size` and `set_maximum_size`; pass `(0, 0)` to
clear a constraint. See `examples/62_window_size_limits` for a manual review.
`WindowHandle::center` places a live window in the work area of its current
monitor while preserving its size. See `examples/63_window_center` for a
manual review.
`WindowHandle::set_movable` controls manual title-bar movement without blocking
programmatic `set_position` or `center` calls. It is enforced on macOS and
Windows and follows Electron's no-op behavior on Linux. See
`examples/64_window_movable` for a manual review.

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
  open_on_start=false,
)
.app_lifecycle(
  on_start=async fn(context) {
    let details = context.windows().open("details")
    details.set_position(80, 80)
    details.set_zoom_percent(110)
  },
  on_shutdown=fn(_) {  },
)
```

Runtime-created windows must be declared before startup so packaging inputs,
origins, and renderer capabilities remain explicit. `open_on_start=false` declares a
template without creating it; `WindowManager::open` creates a fresh concrete
instance when the application needs it. `WindowHandle` supports show, hide,
focus, close, title, size, position, minimize, maximize, restore, fullscreen,
always-on-top, zoom, and a `WindowState` snapshot containing the current
monitor, work area, scale factor, focus, and theme. `WindowHandle::center`
centers a live window within that monitor's work area without changing its
size.

Window state and close requests are delivered by the managed runtime session:

```moonbit
@proton.html("Main", main_html)
.on_window_event(async fn(window, event) noraise {
  match event {
    StateChanged(state) => println(window.id() + ": " + state.theme)
  }
})
.on_window_close_request(async fn(_window) noraise {
  @proton.WindowCloseDecision::Allow
})
```

Close handlers run asynchronously without blocking the native UI thread.
`WindowHandle::close` follows the same cancellable request path; session
cleanup uses the owning destroy lifecycle. The process remains active until
every concrete window has closed. See `examples/45_bridge_multi_window`.

A window can also host additional web contents views, following the Electron
`WebContentsView` model: each view is an independent browser layered above the
window's main page with explicit top-left bounds, visibility, and z-order.
Views are added and removed imperatively through the window handle; per-view
navigation uses `ViewHandle::load_url`, and `App::on_view_event` reports
navigations, loading state, titles, and load failures. Engine support is
reported through the `web_contents_view` runtime feature.

The declarative path attaches a view to the primary window at startup:

```moonbit
@proton
.html("App", sidebar, width=1120, height=720)
.with_view(
  "browser",
  @proton.view("https://example.com/", width=832, height=720, x=288),
)
.load_config()
.run_or_abort()
```

Imperative control uses the window handle:

```moonbit
let panel = window.add_view(
  "panel",
  @proton.view("https://example.com/", width=320, height=240, x=16, y=16),
)
panel.set_bounds(x=16, y=16, width=480, height=320)
panel.set_z_order(1)
panel.load_url("https://moonbitlang.com/")
window.remove_view("panel")
```

See `examples/52_web_contents_view`.

Enable operating-system single-instance routing by calling `.single_instance()`.
The stable application identity comes from `.load_config()` or `.identifier(...)`.

When another process starts, Proton forwards its protocol URLs and document
paths to the primary process before creating CEF, then exits. The primary
process restores and focuses its application window before delivering the typed
activation:

```moonbit
@proton.asset("My App", "frontend/dist/index.html")
.load_config()
.single_instance()
.last_window_closed_policy(@proton.LastWindowClosedPolicy::KeepRunning)
.on_launch_input(async fn(context, input) noraise {
  match input {
    OpenUrls(urls) => ...
    OpenFiles(paths) => ...
    Reopen =>
      if context.windows().find("main") is None {
        ignore(context.windows().open("main")) catch {
          _ => ()
        }
      }
  }
})
```

By default, closing the last window quits the application. Select
`KeepRunning` for applications that should remain available in the Dock or
system tray after their windows close. Call `context.quit()` from an
application-lifetime callback to request an orderly shutdown.

The instance coordinator is implemented on macOS, Windows, and Linux. Packaged
macOS applications register `package.url_schemes` and `package.document_types`
through `Info.plist`. Windows portable ZIPs and the current Linux build do not
install operating-system associations; their `proton-package.json` metadata is
intended for a future installer/package target. Direct launches and associations
installed by another package manager still use the same forwarding path.

Use `app.data_dir()` to resolve the stable native data directory for the
application's configured identifier. The method does not create the directory.

## Logging

Applications log through `tonyfettes/xlog@0.4.1` directly. Use `app.*`
categories for application records; Proton reserves `proton.*` for runtime
diagnostics:

```moonbit
@xlog.info(category="app.sync") <? {
  "message": "synchronization started",
  "account": account_id,
}
```

Packaged applications write `Warn` and above to the platform application log
directory derived from their package metadata. Direct launches and
`proton_cli dev` write to stderr; `proton_cli dev` also selects `Info`.
`MOON_XLOG` controls xlog level and category filters, while
`PROTON_LOG_OUTPUT` selects the initial Proton handler as `file` or `stderr`.
File output requires packaged application metadata. Applications may replace
the global xlog handler or configuration afterwards. CEF's temporary
diagnostic log remains separate under `PROTON_CEF_LOG`.

## Application locale

Proton resolves one immutable locale snapshot before creating the native
runtime. By default it uses the operating system's preferred language order
and appends `en-US` as a fallback. Applications can select an explicit primary
locale while retaining that system preference list:

```moonbit
let locale = @proton.Locale::parse("zh-CN") catch {
  error => abort(error.message())
}
@proton.html("My App", html)
.load_config()
.locale(locale)
.run_or_abort()
```

`ApplicationContext`, `WindowContext`, and `CommandContext` expose `locale()`
and `preferred_languages()`. CEF receives the same values for
`navigator.language`, `navigator.languages`, and HTTP language negotiation.
Standard native menu roles use Proton's built-in framework labels for `en-US`
and `zh-CN`; explicit menu labels are preserved exactly.

Proton does not provide application translation catalogs, message formatting,
or runtime language switching. The application remains responsible for its
page content, dialogs, notifications, and custom menu labels. See
`examples/56_i18n`.

## Native menus

`App::menu` accepts a complete logical `MenuBar`. Use `Menu::role` and
`MenuItem::role` for platform-standard behavior; omitted labels and default
items are resolved from the immutable application locale. Use `Menu` and
`MenuItem::command` for application-defined labels and commands:

```moonbit
@proton.MenuBar(menus=[
  @proton.Menu::role(@proton.MenuRole::Edit),
  @proton.Menu::role(@proton.MenuRole::Window),
  @proton.Menu("Tools", items=[
    @proton.MenuItem::command("tools.refresh", "Refresh", key="r"),
  ]),
])
```

On macOS, Proton inserts an Application menu when absent and places the
`MenuRole::Application` menu first as required by AppKit. Linux renders only
menus supplied by the application. Native application menus are not yet
implemented on Windows, so applications must not call `App::menu` there.
Custom labels remain the application's localization responsibility.

## Headless automation

Code-driven applications can run with CEF off-screen rendering and no native
top-level window:

```moonbit
@proton.html("Automation", html)
.load_config()
.headless()
.run_or_abort()
```

Set `PROTON_HEADLESS=1` to force the same mode in automated runs without
changing application code. Headless mode is independent of remote debugging,
so CDP can be enabled separately for end-to-end tests. Native menus, dialogs,
and titlebar overlay are unavailable in this mode. Linux still requires an
X11 display; use Xvfb in display-less CI jobs.

Development and explicit debug mode use an ephemeral remote-debugging port by
default, and CEF prints the selected WebSocket endpoint to stderr. Set
`PROTON_REMOTE_DEBUGGING_PORT` to `0` to request the same behavior explicitly,
or to a value from `1024` through `65535` when a fixed port is required.

## Frontend projects

Generated projects describe their toolchain in `proton.project.json`:

```json
{
  "identifier": "com.example.my-app",
  "backend": {
    "path": ".",
    "package": "backend/app"
  },
  "frontend": {
    "path": "frontend",
    "dev_url": "http://127.0.0.1:4300",
    "before_dev": "moonx --target native moonbit-community/warren@0.2.7 dev --direct --port 4300",
    "before_build": "moonx --target native moonbit-community/warren@0.2.7 build",
    "dist": "dist"
  }
}
```

`identifier` is the required application identity shared by the runtime and
packaging tools. Calling `.load_config()` loads it from this file during development
and from the sanitized `proton-package.json` inside a packaged application.
Projects without `proton.project.json` must set the same identity directly with
`.identifier("com.example.my-app")`; the two sources cannot be combined. If
such an application is packaged through the lower-level packaging API, Proton
also verifies at startup that its explicit identity matches the packaged
metadata.

`backend` selects the MoonBit package that runs the Proton runtime. The
application entry is declared in MoonBit with `@proton.html`, `url`, `file`, or
`asset`. `backend.path` is the exact working directory passed to Moon; Proton
does not search parent directories for `moon.work`, `moon.mod`, or another
project configuration. Project file paths must be relative and use `/`
separators. The
`frontend` block drives development and build orchestration: `path` is the
frontend working directory, `before_dev`/`before_build` run there, `dev_url`
is the development server to wait for, and `dist` is the build output to
validate (resolved relative to `path`).

`proton_cli dev` runs `frontend.before_dev`, waits for `frontend.dev_url`, and
launches the app in development mode. `proton_cli build` runs
`frontend.before_build`, validates `frontend.dist`, and builds the MoonBit app
for the native target. Vite, Next, and similar tools fit the same shape: point
`path`, `before_dev`, `before_build`, `dev_url`, and `dist` at the equivalent
npm scripts.

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
moon -C cefsetup run . --target native
moon -C e2e test -p moonbit-community/proton/e2e/test \
  --target native --no-parallelize --diagnostic-limit 200
```

Each E2E scenario installs its release CEF helper from the local Proton source
with `moon install --path` into the scenario's temporary directory.

For an application that is already running with CDP enabled, use the typed
driver instead:

```sh
MBT_PROTON_E2E_SCENARIO=41_app_commands \
MBT_CDP_TARGET=9222 moon -C e2e run test --target native
```

## Package

`moonbit-community/proton_package` is the generic host-native packager. It does
not discover Proton projects or know about CEF. `proton_cli package` builds the
application, resolves the runtime and helper installed by `cef setup`, assembles
the complete Proton/CEF layout, and calls `proton_package` to create the native
artifacts. This assembly is an implementation detail of the CLI package
workflow.

Developers packaging an already-built application that does not need Proton's
CEF layout can use `proton_package` directly:

```sh
moon install moonbit-community/proton_package
proton_package \
  --executable ./build/my-app \
  --product-name "My App" \
  --identifier com.example.my-app \
  --version 1.0.0 \
  --format app \
  --output dist
```

The same implementation is available as the
`moonbit-community/proton_package/lib` package. `--config` accepts a reusable
JSON specification; paths in that file are resolved relative to the file.

### Proton projects

The top-level `identifier` is the application's canonical identity. The
`package` block contains the remaining static metadata and payload inputs:

```json
{
  "identifier": "com.example.my-app",
  "package": {
    "product_name": "My App",
    "version": "1.0.0",
    "formats": ["app", "zip"],
    "resources": ["helpers/worker"],
    "sign": {
      "binaries": ["helpers/worker"]
    },
    "url_schemes": ["my-app"],
    "document_types": [
      {
        "name": "Text document",
        "extensions": ["txt", "md"],
        "role": "Editor"
      }
    ],
    "output": "dist"
  }
}
```

`package.resources` copies project files into the package. `package.sign.binaries`
does not copy anything; it names resource files that `proton_cli` must sign.
Both arrays use paths relative to the directory containing `proton.project.json`. For
the example above, the signing target is
`My App.app/Contents/Resources/helpers/worker` on macOS and
`My App/Resources/helpers/worker` in a Windows portable package. Use the platform's actual
filename, such as `helpers/worker.exe`, for a Windows executable. Globs are
allowed for `package.resources` only; every `package.sign.binaries` entry names
one file.

Backend code can locate these files through `@proton.resource_dir()`. It
returns the absolute project directory supplied by `proton_cli dev`, the
packaged resource directory at runtime, or the startup working directory for a
direct run. Joining the same relative path,
such as `helpers/worker`, therefore addresses the same resource before and
after packaging.

Inspect the resolved package plan before creating artifacts:

```sh
proton_cli package --dry-run
proton_cli package
proton_cli package --release
```

The package command performs an incremental debug executable build by default.
Pass `--release` to use MoonBit's release build mode. Package output is written
to `dist` by default.
Icons, resources, output formats, signing, notarization, custom URL schemes, and
macOS document types are configured through `proton.project.json` and package command
options.

The `dmg` format is available on macOS. It creates a compressed disk image
containing the app and an `/Applications` shortcut for drag-to-install:

```sh
proton_cli package --release --format app --format dmg
```

With `--notarize`, Proton submits the DMG when that format is enabled, then
staples and validates both the DMG and the app before creating any requested
ZIP archive. Without a `dmg` format, the existing app notarization flow is
used. Windows supports the `app` and `zip` formats.

### Open an unsigned app on macOS

Apps packaged without `--sign` are ad-hoc signed. When such an app reaches
another Mac through a download (including ZIP archives produced by the
`zip` target), Gatekeeper quarantines it and macOS may launch it from a
randomized App Translocation path. After confirming the app comes from a
trusted source, remove the quarantine attribute from the top-level bundle:

```sh
xattr -d com.apple.quarantine "My App.app"
```

Do not use `xattr -cr`: recent macOS protects `com.apple.provenance`, which
makes recursive removal fail with `Operation not permitted` without clearing
the quarantine. Deleting the attribute from the top-level `.app` (or moving
the app once in Finder) is sufficient. Apps signed and notarized with
`--sign --notarize` skip this step entirely.

When emitting updater metadata, provide a monotonically increasing release
revision as well as the reproducible publication time. The revision is embedded
in the signed app and emitted into the signed manifest fragment:

```sh
proton_cli package --release --format zip \
  --updater-base-url https://example.com/releases \
  --updater-published-at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --updater-revision 42
```

## Diagnose a project

```sh
proton_cli doctor
```

Doctor checks the project configuration, MoonBit toolchain, active platform,
and required Proton runtime and helper installations without changing the
project. Outside a Proton project, it reports environment information and skips
project-specific checks.

Run `proton_cli cef setup` again when the required runtime or helper is missing
or invalid.
Use `PROTON_CEF_LOG=default` temporarily when browser-runtime logs are needed.

See [examples/Readme.md](examples/Readme.md) for runnable examples. Repository
contributors and release maintainers should follow [AGENTS.md](AGENTS.md).

## License

Apache License 2.0. See [LICENSE.md](LICENSE.md).
