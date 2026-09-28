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
        detail="unsupported Linux package architecture: " + arch,
      )
  }
}

///|
/// Builds a desktop entry that starts `exec`. AppImage entries also carry the
/// AppImage version key, which Flatpak's exporter does not recognize.
fn linux_desktop_entry(
  spec : PackageSpec,
  exec~ : String,
  icon~ : String,
  appimage~ : Bool,
) -> String {
  let prefix =
    #|[Desktop Entry]
    #|Type=Application
    #|Terminal=false
    #|Categories=Utility;
  let version = if appimage {
    "X-AppImage-Version=" + spec.version + "\n"
  } else {
    ""
  }
  let mime_types = if spec.url_schemes.length() == 0 {
    ""
  } else {
    "MimeType=" +
    spec.url_schemes.map(scheme => "x-scheme-handler/" + scheme).join(";") +
    ";\n"
  }
  prefix +
  "\nName=" +
  spec.product_name +
  "\nExec=" +
  exec +
  " %U\nIcon=" +
  icon +
  "\n" +
  version +
  mime_types
}

///|
fn linux_desktop_name(spec : PackageSpec) -> String {
  spec.identifier + ".desktop"
}

///|
fn linux_apprun(name : String, desktop_name : String) -> String {
  let prefix =
    #|#!/bin/sh
    #|HERE="$APPDIR"
  prefix +
  "\nexport CHROME_DESKTOP=\"" +
  desktop_name +
  "\"\nexec \"$HERE/usr/bin/" +
  name +
  "\" \"$@\"\n"
}

///|
/// Stages one AppDir-shaped tree and derives every requested Linux format
/// from it. The AppImage uses the whole AppDir; a Flatpak installs its `usr`
/// prefix as `/app`, so every staged file a Flatpak needs must live there.
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
        detail="Linux packages require a PNG icon",
      )
  }
  guard path_is_file(icon) else {
    raise PackagePlanError::MissingIcon(path=icon)
  }
  let name = executable_name(spec.product_name)
  let resources_path = customization.linux_resources_path.unwrap_or(
    "usr/share/" + name,
  )
  if spec.formats.contains(Flatpak) {
    validate_flatpak_app_id(spec.identifier)
    guard resources_path.replace_all(old="\\", new="/").has_prefix("usr/") else {
      raise LinuxPackagingError::InvalidConfiguration(
        detail="the flatpak format requires Linux resources under usr/: " +
          resources_path,
      )
    }
  }
  let appdir = linux_appdir_path(spec)
  remove_tree(appdir)
  errdefer (remove_tree(appdir) catch { _ => () })
  let bin = path_join(appdir, "usr/bin")
  let resources = path_join(appdir, resources_path)
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
    path_join(appdir, linux_desktop_name(spec)),
    linux_desktop_entry(spec, exec=name, icon=name, appimage=true),
  )
  let apprun = path_join(appdir, "AppRun")
  write_text(apprun, linux_apprun(name, linux_desktop_name(spec)))
  @async_fs.chmod(apprun, 0o755)
  prepare(PackageLayout::{
    root: appdir,
    executable: staged_executable,
    resources,
    libraries,
    executables: bin,
  })
  let arch = linux_arch()
  let artifacts : Array[String] = []
  for format in spec.formats {
    match format {
      AppImage => artifacts.push(create_appimage(spec, appdir, name, arch))
      Flatpak => {
        let command = customization.linux_launcher.unwrap_or(name)
        guard path_is_file(path_join(bin, command)) else {
          raise LinuxPackagingError::InvalidConfiguration(
            detail="the Linux launcher was not staged: " + command,
          )
        }
        artifacts.push(
          create_flatpak(spec, path_join(appdir, "usr"), icon, command, arch),
        )
      }
      App | Zip | Dmg | Nsis => ()
    }
  }
  remove_tree(appdir)
  artifacts
}

///|
async fn create_appimage(
  spec : PackageSpec,
  appdir : String,
  name : String,
  arch : String,
) -> String {
  let destination = path_join(
    spec.output,
    name + "-" + spec.version + "-" + arch + ".AppImage",
  )
  let staging = destination + ".staging"
  remove_tree(staging)
  errdefer (remove_tree(staging) catch { _ => () })
  run_linux_tool(
    "create AppImage",
    "appimagetool",
    ["--no-appstream", appdir, staging],
    extra_env={ "ARCH": arch },
  )
  promote(staging, destination)
  destination
}

///|
async fn run_linux_tool(
  stage : String,
  tool : String,
  args : Array[String],
  extra_env? : Map[String, String],
) -> Unit {
  let (code, output) = @process.collect_output_merged(tool, args, extra_env?) catch {
    error =>
      raise LinuxPackagingError::ToolFailure(
        stage~,
        detail=@debug.render(Repr(error)),
      )
  }
  guard code == 0 else {
    raise LinuxPackagingError::ToolFailure(
      stage~,
      detail="exit code " +
        code.to_string() +
        ": " +
        (output.text() catch { _ => "non-UTF-8 output" }),
    )
  }
}
