# Packaging and signing

`proton_cli package` builds and stages a release application from the same
`moon.proton` configuration and active `.proton/runtime.json` used during
development. Packaging does not download or link a second native runtime.

## Bundle configuration

Projects created by the current `proton_cli new` already include a reverse-DNS
identifier and an active bundle targeting `app` and `zip`. Existing projects
must add an `identifier` and enable the bundle block in `moon.proton`:

```moonbit
identifier = "com.example.my-app"

bundle = {
  active: true,
  targets: ["app", "zip"],
  icon: ["icons/icon.icns", "icons/icon.ico"],
  resources: ["resources/**"],
  output: "target/proton-dist",
}
```

For release builds, Proton runs `frontend.before_build`, validates
`frontend.dist` and the production entry, then builds the selected MoonBit
package for the native target. Use `--no-build` only when the matching isolated
package build already exists.

```sh
proton_cli package app
proton_cli package app --dry-run
proton_cli package app --no-build --target zip
```

## macOS layout and metadata

macOS packaging creates `<Product>.app` with the CEF helper nested at:

```text
<Product>.app/Contents/Frameworks/<Product> Helper.app
```

The active Proton runtime, application configuration, frontend assets, and
additional resources are stored below `Contents/Resources`.

Before staging, Proton validates the product name, reverse-DNS bundle
identifier, and macOS version fields. Semantic-version prerelease and build
metadata are removed from `CFBundleShortVersionString`; the numeric core is
normalized to three components. Set `PROTON_MACOS_BUILD_NUMBER` to provide a
different numeric `CFBundleVersion`.

The first configured `.icns` file is copied as `AppIcon.icns`. The
`CFBundleIconFile` key is emitted only when such an icon is configured.

The bundle is assembled beside the destination as a hidden staging app. The
existing destination is replaced only after layout, signing, and optional
notarization succeed. A failed promotion restores the previous application and
cleans the staging directory.

## Development signing

For local packaging diagnostics, explicitly enable ad-hoc signing:

```sh
PROTON_MACOS_ALLOW_ADHOC=1 \
PROTON_MACOS_SIGNING_IDENTITY=- \
  proton_cli package app --sign
```

This mode enables the library-validation exception required by independently
ad-hoc-signed dylibs. It is intended only for local validation and is rejected
when `--notarize` is requested.

After setting up the darwin runtime and example frontend dependencies, run the
repeatable package and launch regression with:

```sh
node scripts/macos_package_smoke.mjs
```

The smoke verifies the nested signatures, property lists, entitlements,
archive, staging cleanup, extracted application launch, and CEF helper process
layout.

## Developer ID signing

Formal distribution requires a `Developer ID Application` identity:

```sh
PROTON_MACOS_SIGNING_IDENTITY="Developer ID Application: Example Inc. (TEAMID)" \
  proton_cli package app --sign
```

Proton signs the CEF framework and runtime libraries before the helper, main
executable, and outer application. It applies hardened runtime options and the
CEF JIT entitlements to the main application and Helper.app, then runs:

```sh
codesign --verify --deep --strict --verbose=2 <Product>.app
```

Set `PROTON_MACOS_ENTITLEMENTS` to replace the generated entitlements plist.
The default Developer ID entitlements do not disable library validation.

## Notarization

Store notarytool credentials in the Keychain, then provide the profile name:

```sh
PROTON_MACOS_SIGNING_IDENTITY="Developer ID Application: Example Inc. (TEAMID)" \
PROTON_NOTARY_PROFILE="proton-notary" \
  proton_cli package app --notarize
```

The notarization flow:

1. creates a temporary upload archive;
2. runs `notarytool submit --wait`;
3. staples the accepted ticket;
4. runs `stapler validate`;
5. runs `spctl --assess --type execute --verbose=4`;
6. removes the temporary upload archive on success or failure;
7. promotes the staged app and creates the requested distribution zip.

## Windows signing

On Windows, the `app` target creates a portable directory beside a sibling
staging directory. Proton validates the full layout, signs and verifies it when
requested, then atomically replaces the previous directory through a backup.
An interrupted backup is restored on the next run, and failed signing or
promotion leaves the previous package in place. The `zip` target is also built
and verified through a staging archive before replacement.

The portable root contains the application executable, `proton.dll`,
`cef_process.exe`, the CEF runtime DLLs and upstream resource data files
required beside `libcef.dll` (including `icudtl.dat`), `Resources/` with the
same resource data and all locales, `moon.proton`,
the production frontend and entry assets, bundle resources, and
`proton-package.json`. Build-time import libraries (`proton.lib` and
`libcef.lib`) and the CEF `bootstrap*.exe` samples are not distributed. The
runtime file list follows CEF's published `CEF_BINARY_FILES` and
`CEF_RESOURCE_FILES` definitions:

<https://github.com/chromiumembedded/cef/blob/76d244268947a52f43755983ef83766a353a1335/cmake/cef_variables.cmake.in>

The generated zip keeps the portable directory as its top-level entry, so it
can be extracted to an arbitrary ordinary directory, including paths that
contain spaces.

Authenticode signing uses these environment variables:

- `PROTON_WINDOWS_CERTIFICATE`
- `PROTON_WINDOWS_CERTIFICATE_PASSWORD`
- `PROTON_WINDOWS_TIMESTAMP_URL`

The certificate path is required when `--sign` is used and must point to an
existing PFX/P12 file. Proton signs only its own binaries: the main executable,
`cef_process.exe`, and `proton.dll`. Every target must exist before signing.
Signing uses SHA-256 and, by default, the RFC3161 timestamp service at
`http://timestamp.digicert.com`. After every signature Proton runs:

```powershell
signtool verify /pa /all /v <target>
```

The Microsoft signatures on `d3dcompiler_47.dll` and `dxil.dll` are verified
but those third-party files are not re-signed. Other CEF binaries are preserved
unchanged.

For an offline development-only diagnostic, set
`PROTON_WINDOWS_TIMESTAMP_URL=none` (an empty value is also accepted). Do not
disable timestamping for a formal release. The certificate password is passed
only to `signtool`; Proton does not include it in command diagnostics.

After setting up the `win32-x64` runtime, run the repeatable development smoke:

```powershell
moon -C cli run . -- -C .. cef setup
powershell -NoProfile -File scripts\windows_package_smoke.ps1
```

The smoke creates a temporary self-signed code-signing certificate and PFX,
temporarily trusts that certificate for `/pa` verification, packages with
`--sign`, checks the portable layout and zip, extracts to a path containing
spaces, launches the real application, verifies its CDP page and helper path,
and confirms helper cleanup. The certificate, PFX, processes, and temporary
directories are removed in `finally`. This is a development pipeline check;
it does not replace a CA-issued Authenticode certificate, RFC3161 timestamping,
or release validation on the target distribution environment.
