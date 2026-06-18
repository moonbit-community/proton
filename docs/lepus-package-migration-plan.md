# Lepus package migration implementation plan

## Goal

Make `justjavac/lepus` the framework package that application developers import
directly, while preserving the existing architecture layers as Lepus subpackages
for the current stage.

The preferred application API becomes package-level and framework-named:

```moonbit
import {
  "justjavac/lepus"
  "justjavac/lepus_ext/fs" @fs
  "justjavac/lepus_ext/path" @path
}

async fn main {
  @lepus.html("Demo", 900, 700, resource, debug=1)
  .extension(@fs.spec())
  .extension(@path.spec())
  .run_or_abort()
}
```

Config-file startup uses the same facade:

```moonbit
import {
  "justjavac/lepus"
  "justjavac/lepus_ext/fs" @fs
  "justjavac/lepus_ext/path" @path
}

async fn main {
  @lepus.from_config_file("app.json")
  .link(@fs.spec())
  .link(@path.spec())
  .run_or_abort()
}
```

Low-level WebView/CEF access remains available, but moves out of the root
package:

```moonbit
import {
  "justjavac/lepus/webview" @webview
}
```

## Current-stage constraints

- Keep `manifest`, `core`, `runtime`, and `bootstrap` as separate packages under
  the Lepus namespace.
- Do not merge those layers into plain files in the root package yet.
- Do not redesign the internal responsibilities of those layers in this
  migration. That is a later refactor.
- Keep the C stub thin. The low-level CEF binding remains in the low-level
  webview package; framework behavior stays in MoonBit.
- Keep extension linking explicit. Apps only link extensions they import and
  register.
- Move built-in extensions to a separate module named `justjavac/lepus_ext`.
- Rename the developer command to `lepus`.
- Do not keep WebView2-specific code paths.
- Preserve extension runtime ids such as `justjavac/lepus-fs` unless there is a
  deliberate manifest compatibility break.

## Target public package map

| Purpose | Target package | Notes |
| --- | --- | --- |
| Main framework facade | `justjavac/lepus` | Preferred user API: `@lepus.html(...)`, `@lepus.from_config_file(...)`. |
| Low-level native webview binding | `justjavac/lepus/webview` | Current `Webview`, `SizeHint`, `bind`, `eval`, CEF stub. |
| App manifest types | `justjavac/lepus/manifest` | Current manifest package kept as a subpackage. |
| JS/native bridge and extension host | `justjavac/lepus/core` | Current core package kept as a subpackage. |
| App/window lifecycle runtime | `justjavac/lepus/runtime` | Current runtime package kept as a subpackage. |
| `app.json` loading/editing | `justjavac/lepus/bootstrap` | Current bootstrap package kept as a subpackage. |
| IPC protocol and websocket helpers | `justjavac/lepus/ipc`, `justjavac/lepus/ipc/ws` | Support package under Lepus. |
| Metadata/catalog tooling | `justjavac/lepus/catalog` | Tooling-facing package; not the normal app API. |
| CLI executable | `justjavac/lepus/cli` | Binary name is `lepus`. |
| CLI codegen library | `justjavac/lepus/cli/codegen` | Used by the CLI package and generated-code tests. |
| Built-in extensions | `justjavac/lepus_ext/<extension>` | Separate extension module/package family. |
| Examples | local `examples` module | Imports `justjavac/lepus` and `justjavac/lepus_ext/*`. |
| E2E tests | local `e2e` module | Imports public packages only. |

## Target repository layout

The root module remains:

```text
moon.mod                       # name = "justjavac/lepus"
src/
  moon.pkg                     # package justjavac/lepus
  webview/
    moon.pkg                   # package justjavac/lepus/webview
    binding.mbt
    webview.mbt
    stub.c
    webview_smoke_test.mbt
  cef_process/
    moon.pkg                   # package justjavac/lepus/cef_process
    main.mbt
  manifest/
    moon.pkg                   # package justjavac/lepus/manifest
    *.mbt
  core/
    moon.pkg                   # package justjavac/lepus/core
    *.mbt
    assets/
  runtime/
    moon.pkg                   # package justjavac/lepus/runtime
    *.mbt
  bootstrap/
    moon.pkg                   # package justjavac/lepus/bootstrap
    *.mbt
    testdata/
  ipc/
    moon.pkg                   # package justjavac/lepus/ipc
    *.mbt
    ws/
      moon.pkg                 # package justjavac/lepus/ipc/ws
      *.mbt
  catalog/
    moon.pkg                   # package justjavac/lepus/catalog
    *.mbt
    testdata/
  cli/
    moon.pkg                   # executable package, bin-name = "lepus"
    main.mbt
    codegen/
      moon.pkg                 # package justjavac/lepus/cli/codegen
      *.mbt
```

The extension module remains separate:

```text
extensions/
  moon.mod                     # name = "justjavac/lepus_ext"
  fs/
    moon.pkg                   # package justjavac/lepus_ext/fs
  path/
    moon.pkg                   # package justjavac/lepus_ext/path
  dialog/
  clipboard/
  shell/
  keepawake/
  microphone/
  ...
```

## File-level migration map

### Root framework facade: `justjavac/lepus`

Move the high-level app package files into `src/` after moving the current
low-level binding out of `src/`.

Files that should become root facade files:

- `app/facade.mbt` -> `src/facade.mbt`
- `app/create.mbt` -> `src/create.mbt`
- `app/builder.mbt` -> `src/builder.mbt` if the builder remains as an advanced
  compatibility API
- `app/types.mbt` -> `src/types.mbt`
- `app/install.mbt` -> `src/install.mbt`
- `app/config_bridge.mbt` -> `src/config_bridge.mbt`
- `app/command_extension.mbt` -> `src/command_extension.mbt`
- `app/command_extension_order.mbt` -> `src/command_extension_order.mbt`
- `app/framework_ipc_transport.mbt` -> `src/framework_ipc_transport.mbt`
- `app/framework_process.mbt` -> `src/framework_process.mbt`
- `app/framework_process_config.mbt` -> `src/framework_process_config.mbt`
- `app/json_helpers.mbt` -> `src/json_helpers.mbt`
- `app/order.mbt` -> `src/order.mbt`
- existing `app/*_wbtest.mbt` -> matching `src/*_wbtest.mbt`

The normal public API should be owned by the root package:

- `pub fn html(...) -> App`
- `pub fn url(...) -> App`
- `pub fn file(...) -> App`
- `pub fn asset(...) -> App`
- `pub fn from_config_file(path : String) -> App`
- `pub fn create_app(...) -> Result[@runtime.App, String]`
- `pub fn create_app_from_file(...) -> Result[@runtime.App, String]`
- `pub type App`
- app command extension types such as `AppCommandExtensionSpec`,
  `AppCommandExtensionContext`, and descriptor types

Use `from_config_file` as the documented name. Do not keep `from_file` in the
root facade during this migration; the shorter name is less explicit and has no
compatibility requirement for this breaking package-path change.

### Low-level webview binding: `justjavac/lepus/webview`

Move the current root package implementation into `src/webview/`:

- `src/binding.mbt` -> `src/webview/binding.mbt`
- `src/webview.mbt` -> `src/webview/webview.mbt`
- `src/stub.c` -> `src/webview/stub.c`
- `src/webview_smoke_test.mbt` -> `src/webview/webview_smoke_test.mbt`
- `src/pkg.generated.mbti` -> regenerate as `src/webview/pkg.generated.mbti`

Update `src/webview/moon.pkg` to own:

- native stub: `stub.c`
- CEF native link flags from `native_link_config.mjs`
- imports: `moonbitlang/core/json`, `justjavac/ffi`

Update all low-level imports from:

```moonbit
"justjavac/lepus" @webview
```

to:

```moonbit
"justjavac/lepus/webview" @webview
```

### Preserved architecture subpackages

These packages move under the Lepus namespace, but their responsibilities stay
unchanged in this stage.

| Current module/package | Target package | Source move |
| --- | --- | --- |
| `justjavac/lepus_manifest` | `justjavac/lepus/manifest` | `manifest/*` -> `src/manifest/*` |
| `justjavac/lepus_core` | `justjavac/lepus/core` | `core/src/*` -> `src/core/*` |
| `justjavac/lepus_runtime` | `justjavac/lepus/runtime` | `runtime/src/*` -> `src/runtime/*` |
| `justjavac/lepus_bootstrap` | `justjavac/lepus/bootstrap` | `bootstrap/*` -> `src/bootstrap/*` |
| `justjavac/lepus_ipc` | `justjavac/lepus/ipc` | `ipc/src/*` -> `src/ipc/*` |
| `justjavac/lepus_ipc/ws` | `justjavac/lepus/ipc/ws` | `ipc/src/ws/*` -> `src/ipc/ws/*` |
| `justjavac/lepus_catalog` | `justjavac/lepus/catalog` | `catalog/*` -> `src/catalog/*` |

The import rewrite is mechanical:

```text
justjavac/lepus_manifest   -> justjavac/lepus/manifest
justjavac/lepus_core       -> justjavac/lepus/core
justjavac/lepus_runtime    -> justjavac/lepus/runtime
justjavac/lepus_bootstrap  -> justjavac/lepus/bootstrap
justjavac/lepus_ipc        -> justjavac/lepus/ipc
justjavac/lepus_ipc/ws     -> justjavac/lepus/ipc/ws
justjavac/lepus_catalog    -> justjavac/lepus/catalog
```

After this stage, the root package can import these subpackages, but those
subpackages must not import the root facade package unless explicitly designed.
The desired dependency flow is:

```text
webview <- core <- runtime <- lepus
manifest <- bootstrap <- lepus
ipc <- core/runtime/lepus
catalog <- cli/tooling/extensions metadata checks
```

### Framework process package

Move:

```text
app/framework -> src/framework
```

The package path becomes `justjavac/lepus/framework` or another internal
subpackage if the MoonBit package layout supports the intended visibility. It
should import the root facade or the specific lower package it needs, not
duplicate startup logic.

### CEF process package

Keep:

```text
src/cef_process
```

Update its imports from the old root binding to:

```moonbit
"justjavac/lepus/webview" @webview
```

Confirm `native_link_config.mjs` still emits the correct subprocess path after
the package move.

### Extensions: `justjavac/lepus_ext`

Change `extensions/moon.mod`:

```text
name = "justjavac/lepus_ext"
```

Update extension package imports:

```text
justjavac/lepus_app      -> justjavac/lepus
justjavac/lepus_core     -> justjavac/lepus/core
justjavac/lepus_catalog  -> justjavac/lepus/catalog
justjavac/lepus          -> justjavac/lepus/webview, only where low-level Webview is required
```

The user-facing import becomes:

```moonbit
import {
  "justjavac/lepus_ext/fs" @fs
  "justjavac/lepus_ext/path" @path
}
```

Generated extension files should refer to `@lepus.AppCommandExtensionSpec` and
`@lepus.AppCommandExtensionContext` after the codegen templates are updated.

Do not rename extension runtime ids in this migration. For example,
`justjavac/lepus-fs` remains the manifest extension id even though the package
path becomes `justjavac/lepus_ext/fs`.

### CLI

Move the CLI into the root Lepus module:

```text
cli/main.mbt -> src/cli/main.mbt
cli/codegen/* -> src/cli/codegen/*
```

Set the executable package to produce:

```text
bin-name = "lepus"
```

Update pre-build commands and docs:

```text
target/lepus-tools/lepus_cli codegen
```

to:

```text
target/lepus-tools/lepus codegen
```

The generated MoonBit code should import the root framework package as
`justjavac/lepus`, not `justjavac/lepus_app`.

## Public API design details

### Preferred ordinary app API

The facade should keep app startup as a single fluent value:

```moonbit
@lepus.html("Demo", 900, 700, resource, debug=1)
.extension(@fs.spec())
.command(generated_app_command_extension())
.run_or_abort()
```

Rules:

- `html`, `url`, `file`, and `asset` create an `App` value.
- `extension(spec)` links and enables the extension.
- `extension_with_options(spec, options)` links and enables with manifest
  options.
- `link(spec)` only links, for config-file startup where `app.json` is the
  source of enablement.
- `command(spec)` registers a command extension.
- `run() -> Result[Unit, String]`.
- `run_or_abort() -> Unit`.
- Ordinary examples should use only `async fn main` as the entry style.

### Config-file API

Use:

```moonbit
@lepus.from_config_file("app.json")
.link(@fs.spec())
.link(@path.spec())
.run_or_abort()
```

Rules:

- `app.json` remains the source of extension enablement.
- `.link(...)` only makes native extension code available.
- `.extension(...)` on config-file apps can either be rejected or documented as
  "link and force enable"; the preferred current behavior should be `.link(...)`
  to reduce ambiguity.

### Low-level escape hatch

Advanced users can still write:

```moonbit
import {
  "justjavac/lepus/webview" @webview
  "justjavac/lepus/core" @core
}
```

This keeps direct extension installation and native Webview operations possible
without making them the default learning path.

## Step-by-step implementation commits

### Commit 1: move low-level binding out of the root package

Suggested subject:

```text
refactor(webview): move low-level binding into webview subpackage
```

Scope:

- Create `src/webview/moon.pkg`.
- Move `binding.mbt`, `webview.mbt`, `stub.c`, and webview smoke tests into
  `src/webview/`.
- Update imports that need the low-level binding to
  `justjavac/lepus/webview`.
- Keep root `src/moon.pkg` temporarily minimal or ready for facade files.
- Validate native stub linking still works.

Validation:

```powershell
moon check --target native --jobs 1 --diagnostic-limit 120
moon run examples\43_cef_bind_smoke --target native
```

### Commit 2: move app facade into `justjavac/lepus`

Suggested subject:

```text
refactor(app): make lepus the public facade package
```

Scope:

- Move high-level app files from `app/` to `src/`.
- Keep or adapt root facade functions: `html`, `url`, `file`, `asset`,
  `from_config_file`.
- Keep lower-level `create_app(...)` and `create_app_from_file(...)` public.
- Update generated interfaces with `moon info`.
- Do not remove the internal architecture subpackages yet.

Validation:

```powershell
moon check --target native --jobs 1 --diagnostic-limit 120
moon test --target native --jobs 1 --diagnostic-limit 120
```

### Commit 3: move preserved architecture layers under Lepus namespace

Suggested subject:

```text
refactor(packages): nest runtime layers under lepus
```

Scope:

- Move `manifest`, `core`, `runtime`, `bootstrap`, `ipc`, and `catalog` into
  root-module subpackages.
- Rewrite imports to the new `justjavac/lepus/...` paths.
- Keep each package's existing `moon.pkg`, tests, assets, and testdata.
- Remove old standalone module entries from `moon.work` after the move.

Validation:

```powershell
moon check --target native --jobs 1 --diagnostic-limit 120
moon test --target native --jobs 1 --diagnostic-limit 120
moon info --target native
```

### Commit 4: rename extensions module to `justjavac/lepus_ext`

Suggested subject:

```text
refactor(extensions): publish builtins under lepus_ext
```

Scope:

- Change `extensions/moon.mod` name.
- Update extension imports to `justjavac/lepus`, `justjavac/lepus/core`, and
  `justjavac/lepus/catalog`.
- Update all example imports to `justjavac/lepus_ext/<name>`.
- Keep extension metadata and runtime ids unchanged.

Validation:

```powershell
moon -C extensions check --target native --jobs 1 --diagnostic-limit 120
moon -C extensions test --target native --jobs 1 --diagnostic-limit 120
```

### Commit 5: rename CLI command to `lepus`

Suggested subject:

```text
refactor(cli): install lepus command
```

Scope:

- Move CLI under the root module or, if kept as a separate module temporarily,
  still change the executable name to `lepus`.
- Update codegen templates to generate imports for `justjavac/lepus`.
- Update extension and example pre-build commands to call
  `target/lepus-tools/lepus`.
- Verify `moon install` or the existing bin-deps flow produces the expected
  executable.

Validation:

```powershell
moon check src\cli --target native --jobs 1 --diagnostic-limit 120
moon test src\cli\codegen --target native --jobs 1 --diagnostic-limit 120
moon install . --bin target\lepus-tools
Test-Path target\lepus-tools\lepus.exe
```

### Commit 6: migrate examples and docs to `@lepus`

Suggested subject:

```text
docs(examples): use lepus facade imports
```

Scope:

- Update README and package docs to show `@lepus.html(...)`.
- Update config examples to `@lepus.from_config_file(...)`.
- Update low-level examples to import `justjavac/lepus/webview` as `@webview`.
- Remove remaining `justjavac/lepus_app` references from ordinary docs.
- Keep examples README aligned with actual example behavior.

Validation:

```powershell
moon -C examples build --target native --jobs 1 --diagnostic-limit 120
node .\scripts\e2e_cdp_smoke.mjs
```

### Commit 7: finish test and e2e cleanup

Suggested subject:

```text
test: align native checks with lepus package layout
```

Scope:

- Update e2e imports and subprocess paths.
- Fix root native tests so `moon test --target native` passes.
- Specifically address the CEF multi-init smoke-test issue. If CEF cannot be
  initialized and shut down repeatedly in one process, keep those checks as
  separate executable/e2e probes rather than multiple same-process unit tests.
- Regenerate `pkg.generated.mbti` files with `moon info`.

Validation:

```powershell
moon fmt
moon check --target native --jobs 1 --diagnostic-limit 120
moon test --target native --jobs 1 --diagnostic-limit 120
moon -C extensions test --target native --jobs 1 --diagnostic-limit 120
moon -C examples build --target native --jobs 1 --diagnostic-limit 120
moon -C e2e build --target native --jobs 1 --diagnostic-limit 120
node .\scripts\e2e_cdp_smoke.mjs
moon info --target native
moon -C extensions info --target native
moon -C examples info --target native
```

## `moon.work` after migration

If the architecture packages and CLI move under the root module, the workspace
should shrink to:

```text
members = [
  ".",
  "./extensions",
  "./examples",
  "./e2e",
]
```

Do not keep removed directories in `moon.work`.

## Compatibility and breaking changes

Breaking import-path changes:

- `justjavac/lepus_app` -> `justjavac/lepus`
- `justjavac/lepus` low-level binding -> `justjavac/lepus/webview`
- `justjavac/lepus_manifest` -> `justjavac/lepus/manifest`
- `justjavac/lepus_core` -> `justjavac/lepus/core`
- `justjavac/lepus_runtime` -> `justjavac/lepus/runtime`
- `justjavac/lepus_bootstrap` -> `justjavac/lepus/bootstrap`
- `extensions/<name>` -> `justjavac/lepus_ext/<name>`
- `lepus_cli` executable -> `lepus`

Compatibility to preserve:

- Existing manifest JSON shape.
- Existing extension metadata shape.
- Existing JS bridge surface:
  - `window.__MoonBit__.core.invokeOp(...)`
  - `window.__MoonBit__.events.on(...)`
  - `window.__MoonBit__.<extension>.*`
- Existing extension runtime ids unless explicitly changed later.
- Low-level `Webview` API semantics, only under the new package path.

## Risks and decisions to verify

1. Package path vs module path

   Moving packages under the root `src/` module is the cleanest way to make
   `manifest/core/runtime/bootstrap` true Lepus subpackages. Keeping separate
   modules named `justjavac/lepus/manifest` would be less file movement, but it
   keeps versioning and workspace complexity split across more modules.

2. Generated code imports

   Codegen templates currently mention `@app`. They must generate code against
   `@lepus`, otherwise examples using generated command extensions will still
   depend on the old package name.

3. CEF test lifecycle

   CEF may not tolerate repeated initialize/shutdown cycles inside a single
   process. Webview smoke tests should reflect that constraint instead of making
   `moon test --target native` flaky or crash-prone.

4. CLI installation path

   The repository has used `target/lepus-tools/lepus_cli`. The migration should
   prove that `target/lepus-tools/lepus` exists and that pre-build commands can
   call it on Windows.

5. Published package granularity

   `justjavac/lepus_ext` is intentionally separate from `justjavac/lepus`.
   Extensions may carry optional native dependencies and should not be pulled
   into every app by importing the framework facade.

## Self-review of this design

This design matches the desired user-facing story: app developers import
`justjavac/lepus` and write `@lepus.html(...)`, while advanced users can still
drop down to `@webview`, `@core`, `@manifest`, or `@runtime` when needed.

It also avoids a premature internal rewrite. `manifest`, `core`, `runtime`, and
`bootstrap` stay as real package boundaries under the Lepus namespace, so later
refactoring can focus on responsibilities and API shape without being mixed into
the import-path migration.

The main cost is a broad mechanical move. That is why the implementation should
be split into reviewable commits and validated after each layer, rather than
doing one large rename plus behavior changes.
