# Scripts

Small repository scripts used by generation workflows.

## `embed_asset.mjs`

Embeds a text file into generated MoonBit source.

```sh
node ./scripts/embed_asset.mjs <input> <output> <identifier>
```

## `verify_generated.mjs`

Checks release metadata and prebuilt ABI metadata, checks the host platform's
prebuilt exports, then checks that committed generated MoonBit files match
their sources. It writes fresh outputs to a temp directory and compares them
against the repository.

```sh
node ./scripts/verify_generated.mjs
```

CI passes `--skip-prebuilt-abi` because each matrix runner verifies its own
prebuilt in the following platform-specific step. The flag retains metadata
validation and generated-file comparison; it skips only dynamic-library symbol
inspection. Release validation should keep using the default command.

Run this before publishing `proton` or `proton_ext`, and after changing any of:

- extension `#proton.command` annotations or `moon.ext` metadata
- `extensions/fs/assets/*.js`
- `extensions/path/assets/*.js`

Published library packages consume committed generated files directly; do not
put `dev_build` or repository-relative codegen rules back into `proton` or
`proton_ext` package metadata.

## `verify_release_metadata.mjs`

Checks that `proton/prebuilt/*/manifest.json` and the `proton new` template
default version match `proton/moon.mod`. It also checks the published-module
dependency chain from `proton_config` into `proton` and `proton_cli`, plus the
CLI's embedded version string.

```sh
node ./scripts/verify_release_metadata.mjs
```

## `bump_version.mbtx`

Bumps every module in `moon.work` to one lockstep release version. The script
refuses to run when module versions have drifted and updates internal dependency
requirements between workspace modules. It runs on MoonBit's default WASM
target, uses `moonbitlang/async` for filesystem operations, and parses workspace
manifests through `moonbitlang/moon_config`.

```sh
moon run scripts/bump_version.mbtx -- patch
moon run scripts/bump_version.mbtx -- minor
moon run scripts/bump_version.mbtx -- major
```

## `verify_prebuilt_abi.mjs`

Checks every shipped Proton prebuilt manifest, declared artifact, and public
header. Pass a platform id to also inspect that platform's dynamic-library
exports against the `PROTON_API` declarations in `native/include/proton_native.h`:

```sh
node ./scripts/verify_prebuilt_abi.mjs --metadata-only
node ./scripts/verify_prebuilt_abi.mjs darwin-arm64
node ./scripts/verify_prebuilt_abi.mjs linux-x64
node ./scripts/verify_prebuilt_abi.mjs win32-x64
```

CI runs the matching symbol check on each platform. Unix builds hide internal
symbols by default, while `PROTON_API` remains the public ABI export marker.
Any extra `proton_*` export fails; platform-specific exceptions are not part of
the shipped ABI. The Windows check also requires the DLL and helper's embedded
source hashes to match their current build inputs.

## `prebuilt_source_hash.mjs`

Computes, records, and verifies a SHA-256 hash of every repository input used
to build each platform's prebuilt runtime. The native-host build workflows
record the hash after staging their artifacts. Ordinary CI verifies all three
manifest hashes, and the Windows ABI check verifies the hash embedded in its
shipped binaries:

```sh
node ./scripts/prebuilt_source_hash.mjs --print win32-x64
node ./scripts/prebuilt_source_hash.mjs --record darwin-arm64
node ./scripts/prebuilt_source_hash.mjs --verify
```

Do not record a hash without rebuilding and testing that platform's staged
runtime first.

Bridge E2E coverage lives in the `e2e/` MoonBit module. Run the complete
self-hosted suite with `moon -C e2e test`; no JavaScript bridge-smoke wrapper is
required.

## `e2e_scaffold_source_smoke.mjs`

Generates the default three-module Todo project outside the repository and
checks its committed code generation, local-source compilation, Warren
frontend build, native backend build, ad-hoc signed macOS app package, typed
commands, live events, ordinary-browser `BridgeUnavailable` state, and clean
process shutdown. This is a source-integration test: it replaces unpublished
registry dependencies in the temporary project with modules from this checkout.
It does not prove that the generated registry dependencies are published.

Build and install the native runtime first, and install Warren:

```sh
moon install moonbit-community/warren
PROTON_NATIVE_DIST="$PWD/native/dist" node ./scripts/e2e_scaffold_source_smoke.mjs
```

## `e2e_scaffold_registry_smoke.mjs`

Runs an installed `proton_cli` in a temporary directory and checks the generated
project without editing its `moon.work`, module manifests, or build rules. This
is the release gate for registry dependency resolution:

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

Set up the darwin runtime and frontend dependencies first, then run:

```sh
moon -C cli run . -- -C .. cef setup
npm --prefix examples/47_dev_extension_js/frontend ci
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

Set up the `win32-x64` runtime first:

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
