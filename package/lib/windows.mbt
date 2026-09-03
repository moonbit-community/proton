///|
priv struct WindowsSigningConfig {
  certificate : String
  password : String
  timestamp : String?
}

///|
fn windows_app_path(spec : PackageSpec) -> String {
  path_join(spec.output, executable_name(spec.product_name))
}

///|
fn windows_staging_path(spec : PackageSpec) -> String {
  path_join(spec.output, "." + executable_name(spec.product_name) + ".staging")
}

///|
fn windows_zip_path(spec : PackageSpec) -> String {
  path_join(spec.output, executable_name(spec.product_name) + ".zip")
}

///|
fn windows_signing_config() -> WindowsSigningConfig raise WindowsPackagingError {
  let certificate = match @env.get_env_var("PROTON_WINDOWS_CERTIFICATE") {
    Some(path) if path.trim().to_owned() != "" => path.trim().to_owned()
    _ =>
      raise WindowsPackagingError::InvalidConfiguration(
        detail="signing requires PROTON_WINDOWS_CERTIFICATE",
      )
  }
  let timestamp = match @env.get_env_var("PROTON_WINDOWS_TIMESTAMP_URL") {
    Some(value) if value.trim().to_owned().to_lower() == "none" => None
    Some(value) if value.trim().to_owned() != "" =>
      Some(value.trim().to_owned())
    _ => Some("http://timestamp.digicert.com")
  }
  WindowsSigningConfig::{
    certificate,
    password: @env.get_env_var("PROTON_WINDOWS_CERTIFICATE_PASSWORD").unwrap_or(
      "",
    ),
    timestamp,
  }
}

///|
async fn run_signtool(args : Array[String], stage : String) -> Unit {
  let (code, output) = @process.collect_output_merged(
    "signtool",
    args,
    no_console_window=true,
  ) catch {
    error =>
      raise WindowsPackagingError::ToolFailure(
        stage~,
        detail=@debug.render(Repr(error)),
      )
  }
  guard code == 0 else {
    raise WindowsPackagingError::ToolFailure(
      stage~,
      detail="exit code " +
        code.to_string() +
        ": " +
        (output.text() catch { _ => "non-UTF-8 output" }),
    )
  }
}

///|
async fn sign_windows_executable(path : String) -> Unit {
  let signing = windows_signing_config()
  guard path_is_file(signing.certificate) else {
    raise WindowsPackagingError::InvalidConfiguration(
      detail="Windows signing certificate is missing: " + signing.certificate,
    )
  }
  let args = ["sign", "/fd", "SHA256", "/f", signing.certificate]
  if signing.password != "" {
    args.push("/p")
    args.push(signing.password)
  }
  match signing.timestamp {
    Some(timestamp) => {
      args.push("/tr")
      args.push(timestamp)
      args.push("/td")
      args.push("SHA256")
    }
    None => ()
  }
  args.push(path)
  run_signtool(args, "sign Windows executable")
  verify_windows_executable(path)
}

///|
async fn verify_windows_executable(path : String) -> Unit {
  guard path_is_file(path) else {
    raise WindowsPackagingError::MissingTarget(path~)
  }
  run_signtool(
    ["verify", "/pa", "/all", "/v", path],
    "verify Windows executable",
  )
}

///|
async fn create_windows_zip(source : String, destination : String) -> Unit {
  let staging = destination + ".staging.zip"
  remove_tree(staging)
  errdefer (remove_tree(staging) catch { _ => () })
  let script =
    #|& {
    #|  $ErrorActionPreference = "Stop"
    #|  Compress-Archive -LiteralPath $env:PROTON_PACKAGE_ZIP_SOURCE -DestinationPath $env:PROTON_PACKAGE_ZIP_DESTINATION -Force
    #|}
  let (code, output) = @process.collect_output_merged(
    "powershell",
    ["-NoProfile", "-NonInteractive", "-Command", script],
    extra_env={
      "PROTON_PACKAGE_ZIP_SOURCE": source,
      "PROTON_PACKAGE_ZIP_DESTINATION": staging,
    },
    no_console_window=true,
  ) catch {
    error =>
      raise WindowsPackagingError::ToolFailure(
        stage="create Windows zip",
        detail=@debug.render(Repr(error)),
      )
  }
  guard code == 0 else {
    raise WindowsPackagingError::ToolFailure(
      stage="create Windows zip",
      detail="exit code " +
        code.to_string() +
        ": " +
        (output.text() catch { _ => "non-UTF-8 output" }),
    )
  }
  promote(staging, destination)
}

///|
async fn package_windows(
  spec : PackageSpec,
  customization : PackageCustomization,
  prepare : async (PackageLayout) -> Unit,
) -> Array[String] {
  guard path_is_file(spec.executable) else {
    raise PackagePlanError::MissingExecutable(path=spec.executable)
  }
  let staging = windows_staging_path(spec)
  remove_tree(staging)
  ensure_dir(staging)
  errdefer (remove_tree(staging) catch { _ => () })
  let name = executable_name(spec.product_name) + ".exe"
  let staged_executable = path_join(staging, name)
  copy_file(spec.executable, staged_executable)
  copy_payloads(spec, path_join(staging, "Resources"), staging, staging)
  stage_windows_icon(spec, staged_executable)
  let layout = PackageLayout::{
    root: staging,
    executable: staged_executable,
    resources: path_join(staging, "Resources"),
    libraries: staging,
    executables: staging,
  }
  prepare(layout)
  if spec.sign {
    let targets = [staged_executable]
    for target in customization.windows_sign_targets {
      let path = path_join(staging, target)
      if !targets.contains(path) {
        targets.push(path)
      }
    }
    for target in targets {
      sign_windows_executable(target)
    }
    for target in customization.windows_verify_targets {
      verify_windows_executable(path_join(staging, target))
    }
  }
  let outputs : Array[String] = []
  let app = windows_app_path(spec)
  promote(staging, app)
  if spec.formats.contains(App) {
    outputs.push(app)
  }
  if spec.formats.contains(Zip) {
    let zip = windows_zip_path(spec)
    create_windows_zip(app, zip)
    outputs.push(zip)
  }
  if spec.formats.contains(Nsis) {
    create_windows_installer(spec, app, false)
    outputs.push(windows_installer_path(spec))
  }
  if !spec.formats.contains(App) {
    remove_tree(app)
  }
  outputs
}
