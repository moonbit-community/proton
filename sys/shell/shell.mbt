///|
/// Returns the shared unsupported-platform error message.
fn unsupported_error_message() -> String {
  "shell package currently supports Windows, macOS, and Linux native builds"
}

///|
/// Returns `true` when the current native target has a shell backend that
/// this package knows how to call.
pub fn is_supported() -> Bool {
  is_supported_ffi()
}

///|
/// Verifies that the current native platform is supported by this package.
///
/// Returns `Ok(())` on supported platforms and an explanatory `Err(String)` on
/// unsupported targets.
pub fn ensure_supported() -> Result[Unit, String] {
  if is_supported() {
    Ok(())
  } else {
    Err(unsupported_error_message())
  }
}

///|
/// A platform shell request could not be completed.
pub suberror ShellError {
  ShellError(operation~ : String, target~ : String, reason~ : String)
} derive(Debug)

///|
pub extend ShellError with Debug::{to_repr}

///|
pub extend ShellError with Show::{to_string, output}

///|
impl Show for ShellError with fn output(self, logger) {
  let ShellError(operation~, target~, reason~) = self
  logger.write_string("shell.\{operation} failed for \{target}: \{reason}")
}

///|
async fn run_tool(
  operation : String,
  target : String,
  tool : String,
  args : Array[String],
) -> Unit raise ShellError {
  let status = @process.run(tool, args) catch {
    error => raise ShellError(operation~, target~, reason=error.to_string())
  }
  if status != 0 {
    raise ShellError(
      operation~,
      target~,
      reason="\{tool} exited with status \{status}",
    )
  }
}

///|
fn check_native_result(
  ok : Bool,
  operation : String,
  target : String,
) -> Unit raise ShellError {
  if !ok {
    raise ShellError(operation~, target~, reason="native shell request failed")
  }
}

///|
fn file_uri(path : String) -> String raise ShellError {
  let absolute = if path.has_prefix("/") {
    path
  } else {
    let cwd = match @env.current_dir() {
      Some(cwd) => cwd
      None =>
        raise ShellError(
          operation="revealItem",
          target=path,
          reason="cannot determine current directory",
        )
    }
    cwd + "/" + path
  }
  // Encode each component, preserving separators and the requested symlink entry.
  "file://" +
  absolute.split("/").map(component => @percent.encode(component)).join("/")
}

///|
/// Opens a URL or filesystem path with its default application.
///
/// Uses ShellExecuteW on Windows, /usr/bin/open on macOS, and gio open on Linux.
/// Linux requires gio and a desktop session with a default handler. Raises
/// ShellError on failure. Waiting for an external tool yields to other tasks;
/// cancellation terminates and reaps the tool using async's process lifecycle.
/// Success means the platform accepted the request, not that the target app
/// finished starting.
pub async fn open(target : String) -> Unit raise ShellError {
  match @async.platform {
    Windows =>
      check_native_result(open_ffi(@ffi.to_cstr(target)), "open", target)
    MacOS => run_tool("open", target, "/usr/bin/open", ["--", target])
    Linux => run_tool("open", target, "gio", ["open", "--", target])
  }
}

///|
/// Opens the native file manager and selects the filesystem entry at `path`.
///
/// Uses Explorer on Windows, /usr/bin/open -R on macOS, and FileManager1
/// ShowItems via dbus-send on Linux. Linux requires dbus-send and a file manager
/// implementing that session-bus interface. Raises ShellError on failure.
/// External-tool waits yield and participate in task cancellation.
pub async fn reveal_item(path : String) -> Unit raise ShellError {
  match @async.platform {
    Windows =>
      check_native_result(
        reveal_item_ffi(@ffi.to_cstr(path)),
        "revealItem",
        path,
      )
    MacOS => run_tool("revealItem", path, "/usr/bin/open", ["-R", "--", path])
    Linux =>
      run_tool("revealItem", path, "dbus-send", [
        "--session",
        "--print-reply=literal",
        "--dest=org.freedesktop.FileManager1",
        "/org/freedesktop/FileManager1",
        "org.freedesktop.FileManager1.ShowItems",
        "array:string:" + file_uri(path),
        "string:",
      ])
  }
}

///|
/// Moves `path` to the operating-system trash or recycle bin.
///
/// Uses the recycle bin on Windows, Finder Trash on macOS, and gio trash on
/// Linux. Raises ShellError on failure. The Linux tool wait yields and
/// participates in task cancellation.
pub async fn trash_item(path : String) -> Unit raise ShellError {
  match @async.platform {
    Linux => run_tool("trashItem", path, "gio", ["trash", "--", path])
    Windows | MacOS =>
      check_native_result(trash_item_ffi(@ffi.to_cstr(path)), "trashItem", path)
  }
}

///|
/// Plays the operating system's default alert sound.
///
/// On Windows this calls `MessageBeep`. On macOS and Linux it writes the
/// terminal bell escape to stderr. Returns `Ok(())` when the platform has a
/// beep backend.
pub fn beep() -> Result[Unit, String] {
  if !is_supported() {
    return Err(unsupported_error_message())
  }
  if beep_ffi() {
    Ok(())
  } else {
    Err("shell.beep failed")
  }
}
