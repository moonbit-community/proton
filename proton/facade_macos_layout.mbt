///|
/// Locate the CEF helper executable inside a macOS `.app` bundle.
///
/// Chromium derives the MachPort rendezvous service name from the main bundle's
/// `CFBundleIdentifier`. A bare `cef_process` helper (no enclosing bundle)
/// computes an empty base bundle id, looks up the wrong service name
/// (`bootstrap_look_up … Unknown service name (1102)`), and every child process
/// terminates — leaving the window blank. The fix is to launch the helper from
/// a nested helper `.app` under `Contents/Frameworks/`: Chromium's outer-bundle
/// walk then climbs out to the main `.app` and yields the same base bundle id
/// the browser uses, so the rendezvous names match.
///
/// This returns the base helper executable path when the host runs from
/// `…/Contents/MacOS/<exe>` and a `Contents/Frameworks/<name> Helper.app`
/// carrying a `Contents/MacOS/<name> Helper` executable is present; otherwise
/// `None`, leaving the runtime to its default subprocess discovery (correct for
/// the unbundled dev flow and for platforms without this constraint).
async fn macos_bundled_helper_path() -> String? {
  guard @env.args().get(0) is Some(exe_path) else { return None }
  let resolved_exe_path = @fs.realpath(exe_path) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  let exe : @mbpath.Path = resolved_exe_path
  let macos_dir = exe.dirname()
  // Only an `.app` layout puts the executable directly under `MacOS`.
  guard macos_dir.basename() == "MacOS" else { return None }
  let frameworks = macos_dir.dirname().join("Frameworks")
  let entries = list_dir(frameworks.to_string())
  for entry in entries {
    if is_base_cef_helper_app(entry) {
      if helper_executable_in_app(frameworks, entry) is Some(path) {
        return Some(path)
      }
    }
  }
  for entry in entries {
    if entry.has_suffix(".app") {
      if helper_executable_in_app(frameworks, entry) is Some(path) {
        return Some(path)
      }
    }
  }
  None
}

///|
fn is_base_cef_helper_app(entry : String) -> Bool {
  entry.has_suffix(" Helper.app")
}

///|
async fn helper_executable_in_app(
  frameworks : @mbpath.Path,
  entry : String,
) -> String? {
  let helper_macos = frameworks.join(entry).join("Contents").join("MacOS")
  let helper_exe = first_regular_file(helper_macos.to_string())
  if helper_exe is Some(name) {
    Some(helper_macos.join(name).to_string())
  } else {
    None
  }
}

///|
/// Directory entries, or an empty list when the path is absent/unreadable.
/// Filesystem failures here are non-fatal — helper discovery falls back to the
/// runtime's default — so they are swallowed, but cancellation is re-raised so
/// the surrounding task group can still tear the runtime down.
async fn list_dir(path : String) -> Array[String] {
  if !(@fs.exists(path) catch {
      error if @async.is_being_cancelled() => raise error
      _ => false
    }) {
    return []
  }
  let dir = @fs.opendir(path) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return []
  }
  let entries = dir.read_all() catch {
    error if @async.is_being_cancelled() => {
      dir.close()
      raise error
    }
    _ => {
      dir.close()
      return []
    }
  }
  dir.close()
  entries
}

///|
/// The first non-directory entry of `dir` (the helper `.app` ships a single
/// executable under `Contents/MacOS`), or `None` when there is none.
async fn first_regular_file(dir : String) -> String? {
  for entry in list_dir(dir) {
    let path = (dir : @mbpath.Path).join(entry).to_string()
    let kind = @fs.kind(path) catch {
      error if @async.is_being_cancelled() => raise error
      _ => continue
    }
    if !(kind is Directory) {
      return Some(entry)
    }
  }
  None
}
