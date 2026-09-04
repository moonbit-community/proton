# proton_package

`proton_package` packages an already-built executable with the current host's
native tools. It does not inspect MoonBit workspaces, build source code, read
`proton.project.json`, or assemble a Proton/CEF runtime.

```sh
proton_package \
  --executable ./build/my-app \
  --product-name "My App" \
  --identifier com.example.my-app \
  --version 1.0.0 \
  --format app \
  --output dist
```

For reusable configuration, pass `--config package.json`:

```json
{
  "schema_version": 1,
  "executable": "build/my-app",
  "product_name": "My App",
  "identifier": "com.example.my-app",
  "version": "1.0.0",
  "formats": ["app", "zip"],
  "output": "dist",
  "payloads": [
    {
      "source": "assets",
      "destination": "assets",
      "location": "resources"
    }
  ]
}
```

Supported host-native formats are macOS `app`, `zip`, and `dmg`; Windows
`app`, `zip`, and `nsis`; and Linux `appimage`.
When no format is specified, macOS and Windows produce `app` and `zip`, while
Linux produces `appimage`.

For Windows NSIS, `--nsis-install-mode` (or `nsis_install_mode` in the JSON
configuration) accepts the same mode names as Tauri:

| Mode | Permissions and scope |
| --- | --- |
| `currentUser` (default) | No elevation; `%LOCALAPPDATA%`; current-user registration and shortcuts. |
| `perMachine` | Administrator privileges; Program Files; machine-wide registration and shortcuts. |
| `both` | NSIS MultiUser selection page; highest available privileges, potentially prompting for elevation. |

The library equivalent is `PackageSpec(..., nsis_install_mode=PerMachine)`.
The mode affects only NSIS installers, not portable directories or ZIP files.
Command-line options override JSON configuration. Installation and uninstall
records, URL schemes, and shortcuts all follow the selected scope.

Applications distributed using Proton's previous machine-wide default must
explicitly select `perMachine` for subsequent releases. Fixed modes reuse
installation paths within their own scope; they do not automatically migrate
an existing machine-wide installation to the current user. The existing NSIS
registry view is retained so `perMachine` can find those older installations.
In `both` mode, `/CurrentUser` and `/AllUsers` select the scope for unattended
installation; `/D=...` may override the directory and must be the last argument.
Automatic updates pass the running application's directory. In `both` mode,
the installer matches that directory to its registered scope and aborts if the
scope is missing or ambiguous, rather than updating a different installation.

The executable and `lib` package support both the wasm and native MoonBit
targets. Windows executable icon embedding uses a native C stub; requesting an
`.ico` while running the wasm build reports that unsupported operation instead
of silently omitting the icon.
