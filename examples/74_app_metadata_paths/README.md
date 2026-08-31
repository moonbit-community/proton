# Application Metadata And Paths

Manual review for Electron-style application metadata, packaged state, and
standard paths.

Run the development form from the repository root:

```sh
PROTON_NO_UPDATE_CHECK=1 moon -C cli run . -- dev -C .. \
  --config examples/74_app_metadata_paths/proton.project.json
```

Verify that the product name is `Proton App Metadata`, the version is `1.2.3`,
and the execution mode is `Development`. Every listed path must be absolute;
user data, session data, and logs must contain the application identifier or
its platform-specific storage hierarchy. Desktop, documents, downloads, music,
pictures, and videos must match the operating system's configured user folders.
`Module` must equal `Executable`; `Assets` is unavailable on macOS, and
`Recent` is available only on Windows.

Build the packaged form:

```sh
moon -C cli run . -- package \
  -C .. \
  --config examples/74_app_metadata_paths/proton.project.json \
  --format app
```

Run the artifact under `dist/` and verify that the execution mode changes to
`Packaged`, while the product name and version remain unchanged. The app path
must point inside the packaged resource layout and the executable path must
point at the packaged binary.

Repeat the development and packaged checks on macOS, Windows, and Linux.
