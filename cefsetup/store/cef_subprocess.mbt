///|
fn subprocess_executable_name(platform : String) -> String {
  if platform.has_prefix("win32-") {
    "cef_process.exe"
  } else {
    "cef_process"
  }
}

///|
fn subprocess_installation_root(
  proton_home : String,
  platform : String,
  version : String,
) -> String {
  path_join(
    path_join(path_join(proton_home, "subprocesses"), platform),
    version,
  )
}

///|
fn subprocess_package(version : String) -> String {
  "moonbit-community/proton/internal/cef_process@" + version
}

///|
fn proton_home() -> String raise CefRuntimeError {
  guard home_directory() is Some(home) else {
    raise CefRuntimeError::StoreRootUnavailable
  }
  resolve_path(home, ".proton")
}

///|
async fn default_subprocess_paths() -> (String, String, String) {
  let requirement = default_requirement()
  let executable_name = subprocess_executable_name(requirement.platform)
  let root = subprocess_installation_root(
    proton_home(),
    requirement.platform,
    release_version(),
  )
  (root, path_join(root, executable_name), executable_name)
}

///|
async fn subprocess_moon_environment() -> Map[String, String] noraise {
  let macos = is_macos_host() catch { _ => false }
  subprocess_moon_environment_for(
    @env.get_env_vars(),
    windows=@path.sep == '\\',
    macos~,
    configured_cc=@env.get_env_var("MOON_CC"),
  )
}

///|
fn subprocess_moon_environment_for(
  environment : Map[String, String],
  windows~ : Bool,
  macos~ : Bool,
  configured_cc~ : String?,
) -> Map[String, String] {
  environment["PROTON_CEF_SETUP_BOOTSTRAP"] = "0"
  if !windows {
    environment["MOON_CC"] = match configured_cc {
      Some(value) if value.trim() != "" => value
      _ => "cc"
    }
  }
  if macos {
    environment["MACOSX_DEPLOYMENT_TARGET"] = "12.0"
  }
  environment
}

///|
async fn subprocess_build_directory() -> String {
  @async_fs.tmpdir(prefix="proton-subprocess-build-") catch {
    error =>
      raise CefSubprocessError::CreateTemporaryDirectory(
        detail=@debug.render(Repr(error)),
      )
  }
}

///|
async fn subprocess_is_valid(path : String) -> Bool {
  guard file_is_nonempty(path) else { return false }
  if @path.sep == '\\' {
    true
  } else {
    @async_fs.can_execute(path) catch {
      error if @async.is_being_cancelled() => raise error
      _ => false
    }
  }
}

///|
/// Resolves the subprocess executable installed for this Proton release.
pub async fn resolve_default_subprocess() -> String {
  let (_, executable, _) = default_subprocess_paths()
  guard subprocess_is_valid(executable) else {
    raise CefSubprocessError::NotInstalled(path=executable)
  }
  executable
}

///|
/// Installs the subprocess executable selected by this Proton release.
async fn install_default_subprocess() -> String {
  let (root, executable, executable_name) = default_subprocess_paths()
  ensure_dir(path_parent(root))
  let lock = acquire_install_lock(root)
  defer lock.close()
  defer lock.unlock()
  if subprocess_is_valid(executable) {
    return executable
  }
  let staging = create_install_staging(root)
  defer (remove_tree(staging) catch { _ => () })
  let build_dir = subprocess_build_directory()
  defer (remove_tree(build_dir) catch { _ => () })
  let args = [
    "install",
    subprocess_package(release_version()),
    "--bin",
    staging,
    "--target-dir",
    build_dir,
  ]
  report_info("[INFO] Installing Proton subprocess: " + executable)
  let code = @process.run(
    "moon",
    args,
    cwd=build_dir,
    extra_env=subprocess_moon_environment(),
    inherit_env=false,
  ) catch {
    error =>
      raise CefSubprocessError::InstallStart(detail=@debug.render(Repr(error)))
  }
  guard code == 0 else { raise CefSubprocessError::InstallExit(code~) }
  let staged_executable = path_join(staging, executable_name)
  guard subprocess_is_valid(staged_executable) else {
    raise CefSubprocessError::InstalledExecutableMissing(path=staged_executable)
  }
  publish_staged_directory(staging, root)
  guard subprocess_is_valid(executable) else {
    raise CefSubprocessError::InstalledExecutableMissing(path=executable)
  }
  executable
}

///|
test "subprocess cache identity includes platform and Proton version" {
  assert_eq(
    subprocess_installation_root("/home/user/.proton", "darwin-arm64", "1.2.3"),
    path_join("/home/user/.proton", "subprocesses/darwin-arm64/1.2.3"),
  )
  assert_eq(subprocess_executable_name("win32-x64"), "cef_process.exe")
  assert_eq(subprocess_executable_name("linux-x64"), "cef_process")
  assert_eq(
    subprocess_package("1.2.3"),
    "moonbit-community/proton/internal/cef_process@1.2.3",
  )
}

///|
test "subprocess build uses the normal Proton native link configuration" {
  assert_eq(
    subprocess_moon_environment_for(
      {},
      windows=false,
      macos=true,
      configured_cc=None,
    ),
    {
      "MACOSX_DEPLOYMENT_TARGET": "12.0",
      "MOON_CC": "cc",
      "PROTON_CEF_SETUP_BOOTSTRAP": "0",
    },
  )
}
