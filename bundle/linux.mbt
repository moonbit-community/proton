///|
/// Keeps the development executable's absolute runtime path out of a packaged
/// AppImage while preserving the shared `bin` + `Resources/proton` layout.
let linux_package_rpath : String = "$ORIGIN/../Resources/proton/bin"

///|
fn proton_linux_apprun(name : String) -> String {
  let prefix =
    #|#!/bin/sh
    #|HERE="$APPDIR"
    #|PROTON_ROOT="$HERE/usr/Resources/proton"
    #|CEF_LIBRARY="$PROTON_ROOT/bin/libcef.so"
    #|export PROTON_RUNTIME_ROOT="$PROTON_ROOT"
    #|export PROTON_HELPER_PATH="$HERE/usr/bin/cef_process"
    #|export LD_LIBRARY_PATH="$PROTON_ROOT/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    #|export LD_PRELOAD="$CEF_LIBRARY${LD_PRELOAD:+:$LD_PRELOAD}"
  prefix + "\nexec \"$HERE/usr/bin/" + name + "\" \"$@\"\n"
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
