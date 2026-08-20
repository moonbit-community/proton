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
proton_cli new my-app --yes
cd my-app
```

Fetch the MoonBit dependencies and set up the native runtime. The generated
project runs its pinned Warren frontend toolchain through `moonx`:

```sh
moon update
proton_cli cef setup
```

Start development:

```sh
proton_cli dev
```

The generated project is a three-module workspace: `shared/` holds the typed
command and event contracts used on both sides, `frontend/` is a Rabbita
application built and served by Warren, and `backend/` runs the Proton
desktop runtime.

`cef setup` installs the exact CEF SDK and runtime required by this Proton
release into the user-wide immutable store at `~/.proton/store`. Every
project using the same Proton release resolves the same installation directly;
projects contain no runtime copy or runtime-selection file. Proton's native
sources are compiled into the application by Moon, while only CEF remains an
external runtime. Set `PROTON_RUNTIME_STORE` to an absolute path to relocate
the store.

## Application entry

Generated projects define application runtime behavior with the MoonBit `App`
builder and register their typed commands in `backend/app/main.mbt`:

```moonbit
async fn main {
  let backend = @todo.Backend::new()
  @proton.asset("My App", "frontend/dist/index.html")
  .single_instance("com.example.my-app")
  .commands(fn(registrar) raise { backend.register_commands(registrar) })
  .permission(
    @proton.PermissionGrant::new(
      "main",
      @proton.PermissionOrigin::Entry,
      "app",
    ),
  )
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
  ).run_or_abort()
}
```

The root package also supports URL, file, and packaged asset entries through
`@proton.url`, `@proton.file`, and `@proton.asset`.

## Renderer permissions

Registering backend commands does not expose them to a renderer. Every
renderer capability requires a grant for one window, one trusted source, and
one extension. Missing grants are denied.

Commands registered directly with `.commands(...)` belong to the `app`
permission id. Grant that capability on the App builder:

```moonbit
.permission(
  @proton.PermissionGrant::new(
    "main",
    @proton.PermissionOrigin::Entry,
    "app",
  ),
)
```

`origin: "app"` names bundled `proton://app` content. `origin: "entry"` follows
the configured entry and resolves URL entries to their exact HTTP(S) origin,
including `frontend.dev_url` during development. Arbitrary origins cannot be
granted.

For extensions without an additional scope, `.expose(extension)` is the
explicit shorthand for registration plus an empty grant. Filesystem access
must declare path ranges and exact commands:

```moonbit
@proton.html("Files", html)
.extension(@fs.extension())
.permission(
  @fs.permission([
    @fs.PermissionRoot::new("./workspace", [
      "read_file",
      "write_file",
      "readdir",
    ]),
  ]),
)
```

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
configured width and height.

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
origins, and permissions remain explicit. `open_on_start=false` declares a
template without creating it; `WindowManager::open` creates a fresh concrete
instance when the application needs it. `WindowHandle` supports show, hide,
focus, close, title, size, position, minimize, maximize, restore, fullscreen,
always-on-top, zoom, and a `WindowState` snapshot containing the current
monitor, work area, scale factor, focus, and theme.

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

Enable operating-system single-instance routing with a stable application
identifier by calling `.single_instance("com.example.my-app")`.

When another process starts, Proton forwards its protocol URLs and document
paths to the primary process before creating CEF, then exits. The primary
process restores and focuses its application window before delivering the typed
activation:

```moonbit
@proton.asset("My App", "frontend/dist/index.html")
.single_instance("com.example.my-app")
.on_launch_input(async fn(input) noraise {
  match input {
    OpenUrls(urls) => ...
    OpenFiles(paths) => ...
    Reopen => ...
  }
})
```

The instance coordinator is implemented on macOS, Windows, and Linux. Packaged
macOS applications register `package.url_schemes` and `package.document_types`
through `Info.plist`. Windows portable ZIPs and the current Linux build do not
install operating-system associations; their `proton-package.json` metadata is
intended for a future installer/package target. Direct launches and associations
installed by another package manager still use the same forwarding path.

Use `@proton.app_data_dir("com.example.my-app")` to resolve the stable native
data directory for an application identifier. The function does not create the
directory.

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
items are resolved from the immutable application locale. Use `Menu::new` and
`MenuItem::command` for application-defined labels and commands:

```moonbit
@proton.MenuBar::new(menus=[
  @proton.Menu::role(@proton.MenuRole::Edit),
  @proton.Menu::role(@proton.MenuRole::Window),
  @proton.Menu::new("Tools", items=[
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
.headless()
.run_or_abort()
```

Set `PROTON_HEADLESS=1` to force the same mode in automated runs without
changing application code. Headless mode is independent of remote debugging,
so CDP can be enabled separately for end-to-end tests. Native menus, dialogs,
and titlebar overlay are unavailable in this mode. Linux still requires an
X11 display; use Xvfb in display-less CI jobs.

## Frontend projects

Generated projects describe their toolchain in `proton.project.json`:

```json
{
  "backend": {
    "path": "backend",
    "package": "app"
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

`backend` selects the MoonBit package that runs the Proton runtime. The
application entry is declared in MoonBit with `@proton.html`, `url`, `file`, or
`asset`. Project file paths must be relative and use `/` separators. The
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
application and helper, then delegates Proton's runtime and helper bundle layout
to `moonbit-community/proton_bundle`, which in turn calls `proton_package`.

Developers who do not use `proton_cli` can use the same layers directly: build
the application executable, install the matching `cef_process` executable, and
pass both explicit paths to `proton_bundle`. Use `proton_package` alone only for
applications that do not need Proton's CEF layout:

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

The `package` block in `proton.project.json` contains the static metadata and
payload inputs needed before the application can run:

```json
{
  "package": {
    "product_name": "My App",
    "identifier": "com.example.my-app",
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
Icons, resources, output targets, signing, notarization, custom URL schemes, and
macOS document types are configured through `proton.project.json` and package command
options.

The `dmg` target is available on macOS. It creates a compressed disk image
containing the app and an `/Applications` shortcut for drag-to-install:

```sh
proton_cli package --release --target app --target dmg
```

With `--notarize`, Proton submits the DMG when that target is enabled, then
staples and validates both the DMG and the app before creating any requested
ZIP archive. Without a `dmg` target, the existing app notarization flow is
used. Windows supports the `app` and `zip` targets.

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
proton_cli package --release --target zip \
  --updater-base-url https://example.com/releases \
  --updater-published-at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --updater-revision 42
```

## Diagnose a project

```sh
proton_cli doctor
```

Doctor checks the project configuration, MoonBit toolchain, active platform,
and required Proton runtime installation without changing the project. Outside a Proton
project, it reports environment information and skips project-specific checks.

Run `proton_cli cef setup` again when the required runtime is missing or invalid.
Use `PROTON_CEF_LOG=default` temporarily when browser-runtime logs are needed.

See [examples/Readme.md](examples/Readme.md) for runnable examples. Repository
contributors and release maintainers should follow [AGENTS.md](AGENTS.md).

## License

Apache License 2.0. See [LICENSE.md](LICENSE.md).
