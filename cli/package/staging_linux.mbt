///|
/// Keeps the development executable's absolute runtime path out of a packaged
/// AppImage while preserving the shared `bin` + `Resources/proton` layout.
let linux_package_rpath : String = "$ORIGIN/../Resources/proton/bin"

///|
/// Names the launcher staged beside the executable. Formats that install the
/// staged `usr` prefix elsewhere, such as Flatpak's `/app`, start the
/// application through it because it locates the prefix from its own path.
let linux_launcher_name : String = "proton-launcher"

///|
/// Establishes the CEF loader environment for the executable in
/// `$PREFIX/bin`. `prefix` is a shell assignment that sets `PREFIX`.
fn proton_linux_launch_script(prefix : String, name : String) -> String {
  let body =
    #|PROTON_ROOT="$PREFIX/Resources/proton"
    #|CEF_LIBRARY="$PROTON_ROOT/bin/libcef.so"
    #|export PROTON_RUNTIME_ROOT="$PROTON_ROOT"
    #|export PROTON_HELPER_PATH="$PREFIX/bin/cef_process"
    #|export LD_LIBRARY_PATH="$PROTON_ROOT/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    #|export LD_PRELOAD="$CEF_LIBRARY${LD_PRELOAD:+:$LD_PRELOAD}"
  "#!/bin/sh\n" +
  prefix +
  "\n" +
  body +
  "\nexec \"$PREFIX/bin/" +
  name +
  "\" \"$@\"\n"
}

///|
fn proton_linux_apprun(name : String) -> String {
  proton_linux_launch_script("PREFIX=\"$APPDIR/usr\"", name)
}

///|
fn proton_linux_launcher(name : String) -> String {
  proton_linux_launch_script(
    "PREFIX=\"$(dirname \"$(dirname \"$(readlink -f \"$0\")\")\")\"", name,
  )
}

///|
/// Selects the shared libraries in a packaged runtime `bin` directory.
fn linux_shared_libraries(names : Array[String]) -> Array[String] {
  names.filter(name => name.has_suffix(".so") || name.contains(".so."))
}

///|
/// CEF's Linux runtime ships its libraries with full debug info, about two
/// thirds of `libcef.so`. Packages drop it; the immutable store keeps the
/// original for development builds.
async fn strip_linux_runtime_libraries(runtime_bin : String) -> Unit {
  let names = @async_fs.readdir(runtime_bin, sort=true)
  for name in linux_shared_libraries(names) {
    let library = resolve_path(runtime_bin, name)
    let code = @process.run("strip", ["--strip-debug", library]) catch {
      error =>
        raise LinuxBundleError::ToolFailure(
          stage="strip debug info",
          detail="strip is not available: \{@debug.render(Repr(error))}",
        )
    }
    guard code == 0 else {
      raise LinuxBundleError::ToolFailure(
        stage="strip debug info",
        detail="strip exited with code \{code}: \{library}",
      )
    }
  }
}

///|
async fn set_linux_rpath(binary : String, rpath : String) -> Unit {
  let code = @process.run("patchelf", ["--set-rpath", rpath, binary]) catch {
    error =>
      raise LinuxBundleError::ToolFailure(
        stage="set rpath",
        detail="patchelf is not available: \{@debug.render(Repr(error))}",
      )
  }
  guard code == 0 else {
    raise LinuxBundleError::ToolFailure(
      stage="set rpath",
      detail="patchelf exited with code \{code}: \{binary}",
    )
  }
}
