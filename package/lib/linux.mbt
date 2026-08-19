///|
fn linux_appdir_path(spec : PackageSpec) -> String {
  path_join(spec.output, "." + executable_name(spec.product_name) + ".AppDir")
}

///|
async fn linux_arch() -> String {
  let (code, output) = @process.collect_output_merged("uname", ["-m"]) catch {
    error =>
      raise LinuxPackagingError::ToolFailure(
        stage="detect architecture",
        detail=@debug.render(Repr(error)),
      )
  }
  guard code == 0 else {
    raise LinuxPackagingError::ToolFailure(
      stage="detect architecture",
      detail="uname exited with code " + code.to_string(),
    )
  }
  match (output.text() catch { _ => "" }).trim().to_owned() {
    "x86_64" | "amd64" => "x86_64"
    "aarch64" | "arm64" => "aarch64"
    arch =>
      raise LinuxPackagingError::InvalidConfiguration(
        detail="unsupported AppImage architecture: " + arch,
      )
  }
}

///|
fn linux_desktop_entry(spec : PackageSpec, name : String) -> String {
  let prefix =
    #|[Desktop Entry]
    #|Type=Application
    #|Terminal=false
    #|Categories=Utility;
  prefix +
  "Name=" +
  spec.product_name +
  "\n" +
  "Exec=" +
  name +
  "\n" +
  "Icon=" +
  name +
  "\n" +
  "X-AppImage-Version=" +
  spec.version +
  "\n"
}

///|
fn linux_apprun(name : String) -> String {
  let prefix =
    #|#!/bin/sh
    #|HERE="$(dirname "$(readlink -f "$0")")"
  prefix + "exec \"$HERE/usr/bin/" + name + "\" \"$@\"\n"
}

///|
async fn package_linux(
  spec : PackageSpec,
  customization : PackageCustomization,
  prepare : async (PackageLayout) -> Unit,
) -> Array[String] {
  guard path_is_file(spec.executable) else {
    raise PackagePlanError::MissingExecutable(path=spec.executable)
  }
  let icon = match first_icon(spec, ".png") {
    Some(icon) => icon
    None =>
      raise LinuxPackagingError::InvalidConfiguration(
        detail="the appimage format requires a PNG icon",
      )
  }
  guard path_is_file(icon) else {
    raise PackagePlanError::MissingIcon(path=icon)
  }
  let appdir = linux_appdir_path(spec)
  remove_tree(appdir)
  errdefer (remove_tree(appdir) catch { _ => () })
  let name = executable_name(spec.product_name)
  let bin = path_join(appdir, "usr/bin")
  let resources = path_join(
    appdir,
    customization.linux_resources_path.unwrap_or("usr/share/" + name),
  )
  let libraries = path_join(appdir, "usr/lib")
  for directory in [bin, resources, libraries] {
    ensure_dir(directory)
  }
  let staged_executable = path_join(bin, name)
  copy_file(spec.executable, staged_executable)
  @async_fs.chmod(staged_executable, 0o755)
  copy_payloads(spec, resources, libraries, bin)
  copy_file(icon, path_join(appdir, name + ".png"))
  copy_file(icon, path_join(appdir, ".DirIcon"))
  write_text(
    path_join(appdir, name + ".desktop"),
    linux_desktop_entry(spec, name),
  )
  let apprun = path_join(appdir, "AppRun")
  write_text(apprun, linux_apprun(name))
  @async_fs.chmod(apprun, 0o755)
  prepare(PackageLayout::{
    root: appdir,
    executable: staged_executable,
    resources,
    libraries,
    executables: bin,
  })
  let arch = linux_arch()
  let destination = path_join(
    spec.output,
    name + "-" + spec.version + "-" + arch + ".AppImage",
  )
  let staging = destination + ".staging"
  remove_tree(staging)
  errdefer (remove_tree(staging) catch { _ => () })
  let (code, output) = @process.collect_output_merged(
    "appimagetool",
    ["--no-appstream", appdir, staging],
    extra_env={ "ARCH": arch },
  ) catch {
    error =>
      raise LinuxPackagingError::ToolFailure(
        stage="create AppImage",
        detail=@debug.render(Repr(error)),
      )
  }
  guard code == 0 else {
    raise LinuxPackagingError::ToolFailure(
      stage="create AppImage",
      detail="exit code " +
        code.to_string() +
        ": " +
        (output.text() catch { _ => "non-UTF-8 output" }),
    )
  }
  promote(staging, destination)
  remove_tree(appdir)
  [destination]
}
