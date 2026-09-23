# Using native capabilities

Extensions expose reusable host operations to the renderer. A capability installs an extension's backend handlers and grants access to a specific scope. This guide reads one local text file from the minimal application.

## Add the filesystem extension

In the minimal project's **`moon.mod`**, add this dependency inside `import { ... }`:

```text
"moonbit-community/proton_ext@0.3.3",
```

Use these imports in **`app/moon.pkg`**, then run `moon update`:

```text
import {
  "moonbitlang/async",
  "moonbit-community/proton",
  "moonbit-community/proton_ext/fs",
}

supported_targets = "native"

pkgtype(kind: "executable")
```

## Prepare a file

Create a directory named **`workspace`** at the project root. Inside it, create **`message.txt`** containing:

```text
Hello from the filesystem.
```

Replace **`app/main.mbt`** with:

```moonbit
///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html lang="en">
    #|<meta charset="utf-8">
    #|<title>Read a file</title>
    #|<button id="read">Read message.txt</button>
    #|<pre id="result" role="status"></pre>
    #|<script>
    #|  document.querySelector("#read").onclick = async () => {
    #|    const result = document.querySelector("#result");
    #|    try {
    #|      const reply = await window.__MoonBit__.core.invokeOp(
    #|        "ext:fs/read_file", { path: "./workspace/message.txt" }
    #|      );
    #|      result.textContent = reply.content;
    #|    } catch (error) {
    #|      result.textContent = String(error);
    #|    }
    #|  };
    #|</script>
    #|</html>
  @proton.html("Read a file", html)
  .load_config()
  .capability(
    @fs.capability([
      @fs.PermissionRoot("./workspace", ["read_file"]),
    ]),
  )
  .run_or_abort()
}
```

Run `proton_cli dev` and click **Read message.txt**. The page should display the file contents. This is an actual host filesystem read, not a browser file picker.

## Understand the grant

The capability has three relevant choices:

- **Operation:** only `read_file` is allowed; this page cannot use this grant to write or delete.
- **Root:** only paths inside `./workspace` are allowed.
- **Target:** with no explicit `targets`, the grant applies to the main window entry.

The low-level route `ext:fs/read_file` belongs to the filesystem extension. Application commands use the separate `app:` route space. You do not register the filesystem handler yourself.

Relative roots and requests resolve against `@proton.resource_dir()`, which the CLI configures for the application. Do not assume they resolve against an arbitrary terminal working directory.

## Check failures deliberately

Change the request path to a missing file within `workspace`: the call should fail and the catch block should show the error. Change it to a file outside the allowed root: the grant should reject access.

Removing `.capability(...)` does not stop the app from starting, but the route becomes unavailable. Adding an extension dependency alone is not a permission grant.

## Multiple windows and persistent files

For a second window, select explicit `RendererTarget::entry(window="...")` or `RendererTarget::bundled(window="...")` targets when adding the capability. Grant each page only what its feature requires.

The local workspace directory is useful for this development exercise. Installed resources may be read-only; use an appropriate writable application-data or user-selected directory for persistent files. Package files you intentionally ship via [resources configuration](../configuration/index.md).

## Other capabilities

Dialogs, clipboard, shell, tray, and other extensions follow the same explicit installation/grant model, but each defines its own scope and platform support. The notification extension in this release targets macOS; do not infer platform support from the framework's overall platform list.

Consult the [extension API](https://mooncakes.io/docs/moonbit-community/proton_ext@0.3.3/) for the capability builder and request/response types you need.
