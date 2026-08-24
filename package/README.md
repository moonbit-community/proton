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

The executable and `lib` package support both the wasm and native MoonBit
targets. Windows executable icon embedding uses a native C stub; requesting an
`.ico` while running the wasm build reports that unsupported operation instead
of silently omitting the icon.
