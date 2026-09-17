# Build and distribute

[中文](zh/packaging.html)

A build produces your executable and frontend output. Packaging assembles them with the runtime, helper, and declared resources into a platform-specific distributable. Use the **Proton CLI** for a Proton project.

## Prepare application metadata

In the existing `package` object of **`proton.project.json`**, set your application name and version:

```json
{
  "product_name": "Todo App",
  "version": "0.1.0",
  "output": "dist"
}
```

Merge these fields rather than replacing the whole project file. Keep the root `identifier` stable across releases. `package.version` is your app version; it does not need to equal Proton 0.3.0.

## Build for release

From the project root:

```sh
proton_cli build -- --release
```

The CLI builds the configured frontend before the native backend. The `--release` after `--` is passed to Moon. A successful command is a build check; it has not produced the final installer.

## Review and package

```sh
proton_cli package --release --dry-run
proton_cli package --release
```

The dry run prints the selected backend, metadata, formats, output, and signing choices. It does not execute the full build/packaging/signing flow. The second command builds and assembles the actual artifacts.

Outputs go to `dist` unless configured otherwise. Inspect the command's output for their exact paths.

## Choose a platform format

Build on the intended target operating system. Proton does not turn these commands into a cross-compilation workflow.

- **macOS Apple Silicon:** `app` creates an app bundle, `zip` an archive, and `dmg` a disk image.
- **Windows x64:** `app` creates an application directory, `zip` a portable archive, and `nsis` an installer.
- **Linux x64:** `appimage` creates an AppImage. Validate it on the Linux environments you support.

Defaults are app and zip on macOS/Windows, and appimage on Linux. Override a single invocation with repeated `--format` flags, or merge this fragment into the existing `package` object:

```json
{
  "platforms": {
    "macos": { "formats": ["app", "dmg"] },
    "windows": { "formats": ["nsis"], "nsis_install_mode": "currentUser" },
    "linux": { "formats": ["appimage"] }
  }
}
```

Each platform list replaces the shared `package.formats` list. Install NSIS before requesting the Windows installer; the Windows SDK resource compiler is needed for executable icons.

## Windows installation scope

`currentUser` is the default: installation for the current user without administrator privileges. `perMachine` installs for all users with elevation. `both` lets the installer choose scope and can prompt for elevation even for a current-user installation.

If an earlier app release used a machine-wide installer, retain `perMachine` explicitly for its updates. Changing the setting does not migrate an existing installation between scopes.

## Signing and notarization

Local packaging does not by itself establish a trusted publisher identity. On macOS, `--sign` requests signing; `--notarize` submits, staples, and validates distributable artifacts using configured credentials.

Before a public release, inspect the current signing options:

```sh
proton_cli package --help
```

Configure your own signing identity and credentials for the target platform. Do not put private signing credentials into application source. See the [packaging reference](https://github.com/moonbit-community/proton#packaging) for the supported options; repository documentation can move ahead of this guide's release.

## Verify the artifact you will ship

Stop the development server and launch the packaged application outside the source checkout. Check:

1. The frontend loads its packaged assets without a localhost server.
2. Commands and required native capabilities work.
3. Declared sidecar resources can be read, and writable data uses the intended location.
4. Window close and explicit quit behavior match the application's lifecycle policy.

For the Todo tutorial, add items and use Complete all/Reopen all in the packaged app. Only then distribute the artifact. Build checks and a packaging dry run do not exercise that final runtime.
