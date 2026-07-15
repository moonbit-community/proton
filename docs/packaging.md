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

On Windows, the `app` target creates a portable directory and `zip` archives
it. Authenticode signing uses these environment variables:

- `PROTON_WINDOWS_CERTIFICATE`
- `PROTON_WINDOWS_CERTIFICATE_PASSWORD`
- `PROTON_WINDOWS_TIMESTAMP_URL`

The certificate path is required when `--sign` is used; the password and
timestamp URL are optional.
