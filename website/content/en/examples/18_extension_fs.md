# Filesystem capability

A renderer requests file operations within an explicit permission root.

[18_extension_fs](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/18_extension_fs) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/18_extension_fs/main.mbt), [fs.html](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/18_extension_fs/fs.html)

## Behavior

The page exposes read, write and directory operations. The native entry registers the fs capability with a PermissionRoot and an operation allowlist.

```moonbit
///|
async fn main {
  @proton.html("18 extension fs", resource, width=960, height=720, debug=true)
  .capability(
    @fs.capability([
      @fs.PermissionRoot(".", [
        "read_file", "write_file", "exists", "kind", "size", "readdir", "mkdir",
        "remove", "rmdir", "rename", "realpath",
      ]),
    ]),
  )
  .identifier("dev.proton.18-extension-fs")
  .run_or_abort()
}
```

## Run

[Environment requirements](../introduction/installation.md) apply. From the checked-out repository root:

```sh
moon -C examples run 18_extension_fs --target native
```

## Limits and interpretation

The example grants write and deletion operations under its working directory. Use a disposable directory for experiments; production apps should grant only their required paths and operations.

## Key code and design

The backend installs the filesystem extension and chooses both its root and allowed operations. The renderer supplies a path and operation, but cannot grant itself a wider root. A missing file and an unauthorized operation are separate failure cases.

This example grants write/delete access for demonstration. In an application, narrow the list to the required operations and use a deliberate data directory. The page's HTML and JavaScript demonstrate the raw extension bridge; MoonBit frontends can use typed descriptors.
