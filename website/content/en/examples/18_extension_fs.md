# Filesystem capability

[中文](../zh/examples/18_extension_fs.html)

A renderer requests file operations within an explicit permission root.

[18_extension_fs](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/18_extension_fs) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/18_extension_fs/main.mbt), [fs.html](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/18_extension_fs/fs.html)

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
