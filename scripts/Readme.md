# Scripts

Small repository scripts used by generation workflows.

## `test_auto_launch_linux.mjs`

Generates an isolated autostart entry through the public MoonBit API, launches it
through GLib and a systemd-generated user service, and checks the application's
actual arguments. Requires Linux, MoonBit, a C compiler, GLib development files,
Python 3, and a running systemd user manager with a session bus. Temporary entries
and services are removed afterward.

```sh
node scripts/test_auto_launch_linux.mjs
```

## `embed_asset.mjs`

Embeds a text file into generated MoonBit source.

```sh
node ./scripts/embed_asset.mjs <input> <output> <identifier>
```

## `verify_generated.mjs`

Checks release metadata and that committed generated MoonBit and native bridge
files match their sources. It builds the standalone `proton_codegen` WASM
executable, writes fresh outputs to a temp directory, and compares them against
the repository.

```sh
node ./scripts/verify_generated.mjs
```

Run this before publishing `proton` or `proton_ext`, and after changing any of:

- extension `#proton.command` annotations or `proton.ext.json` metadata
- `extensions/fs/assets/*.js`
- `extensions/path/assets/*.js`

## `verify_release_metadata.mjs`

Checks workspace lockstep versions, internal dependency requirements and the
CLI's embedded version string. Templates independently reference published
dependencies; their compilation is checked by the scaffold smoke test.

```sh
node ./scripts/verify_release_metadata.mjs
```

## `e2e_scaffold_source_smoke.mjs`

Generates both templates using `moonx moonbit-community/moon-new` against a
local Git snapshot of `templates/`, then checks registry compilation and existing
project protection. `--scaffold-only` stops after these checks on any platform.

The full run also checks the default Todo scaffold's explicit command bindings, local-source
compilation, Warren frontend, native backend, typed commands, business errors,
and ad-hoc signed macOS packaging. A resource marker verifies that repackaging
ships rebuilt frontend assets.

A separate fixed backend fixture then exercises independent window invalidations,
cancelled searches, and the generated internal query module in a real directory
browser (navigation, errors, retry, retained data, and component disposal), plus
ordinary-browser `BridgeUnavailable` state and clean process shutdown. The fixture
is installed as an additional application package; generated application source
is not rewritten. This is a source-integration test: its temporary workspace
resolves Proton modules from this checkout, not the registry.

The script installs the pinned Warren version with `moon install`. The
script configures the shared CEF runtime itself:

```sh
node ./scripts/e2e_scaffold_source_smoke.mjs
```

## `e2e_scaffold_registry_smoke.mjs`

Runs an installed `proton_cli` in a temporary directory and checks the generated
project against its declared registry dependencies. It then uses
`moon add --upgrade` to exercise the newly published Proton release, without workspace
or source overrides. This is the release gate for registry dependency resolution.
It intentionally calls `proton_cli new` to test the wrapper; application developers
can also [invoke moon-new directly](../cli/README.md).

```sh
moon install moonbit-community/proton_cli
node ./scripts/e2e_scaffold_registry_smoke.mjs
```

Set `PROTON_REGISTRY_CLI` only when the registry-installed executable has a
different path. This smoke is expected to fail before every module version
referenced by the template has been published.

## `macos_package_smoke.mjs`

Runs the development-mode macOS packaging regression with an explicit ad-hoc
identity. It builds and packages `47_dev_extension_js`, verifies every nested
signature plus the plist, entitlements, archive, and staging cleanup, then
extracts the zip to a temporary directory and confirms that the real CEF bundle
starts with three nested Helper.app processes.

Set up the darwin runtime and Warren first, then run:

```sh
moon -C cli run . -- -C .. cef setup
moon install moonbit-community/warren@0.4.5
node ./scripts/macos_package_smoke.mjs
```

This is a local development check. It does not replace Developer ID signing,
Apple notarization, or the final Gatekeeper assessment used for a release.

## `windows_package_smoke.ps1`

Runs the Windows portable packaging regression with a temporary self-signed
Code Signing certificate. It packages `47_dev_extension_js` with `--sign`,
verifies the Proton-owned executable, helper, and DLL with Authenticode, checks
the runtime layout and zip, extracts to a path containing spaces, launches the
real CEF application, confirms the CDP page comes from the extracted package,
and checks the helper executable path and cleanup.

Set up the `win32-x64` runtime and install Warren with
`moon install moonbit-community/warren@0.4.5` first:

```powershell
moon -C cli run . -- -C .. cef setup
powershell -NoProfile -File scripts\windows_package_smoke.ps1
```

The script temporarily installs its self-signed certificate in the current
user trust store so `signtool verify /pa /all /v` can validate the development
signature. It removes the certificate, PFX, temporary directories, and any
remaining processes in `finally`. If local policy blocks temporary certificate
creation or trust, the smoke fails with a diagnostic. This check does not
replace a CA-issued release certificate or RFC3161 timestamp validation.
