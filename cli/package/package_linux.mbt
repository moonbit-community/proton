///|
/// Keeps the development executable's absolute runtime path out of a packaged
/// AppImage while preserving the shared `bin` + `Resources/proton` layout.
let linux_package_rpath : String = "$ORIGIN/../Resources/proton/lib"

///|
async fn set_linux_rpath(binary : String, rpath : String) -> Unit {
  let code = @process.run("patchelf", ["--set-rpath", rpath, binary]) catch {
    error =>
      raise LinuxPackagingError::ToolFailure(
        stage="set rpath",
        detail="patchelf is not available: \{@debug.render(Repr(error))}",
      )
  }
  guard code == 0 else {
    raise LinuxPackagingError::ToolFailure(
      stage="set rpath",
      detail="patchelf exited with code \{code}: \{binary}",
    )
  }
}
