///|
let windows_default_timestamp_url = "http://timestamp.digicert.com"

///|
struct WindowsSignTool {
  executable : String
  prefix_args : Array[String]
} derive(Debug, Eq)

///|
struct WindowsSigningConfig {
  certificate : String
  password : String
  timestamp : String?
} derive(Debug, Eq)

///|
fn default_windows_sign_tool() -> WindowsSignTool {
  { executable: "signtool", prefix_args: [] }
}

///|
fn windows_runtime_binary_files() -> Array[String] {
  [
    "proton.dll", "cef_process.exe", "chrome_elf.dll", "d3dcompiler_47.dll", "dxcompiler.dll",
    "dxil.dll", "libcef.dll", "libEGL.dll", "libGLESv2.dll", "v8_context_snapshot.bin",
    "vk_swiftshader.dll", "vk_swiftshader_icd.json", "vulkan-1.dll",
  ]
}

///|
fn windows_runtime_resource_files() -> Array[String] {
  [
    "chrome_100_percent.pak", "chrome_200_percent.pak", "icudtl.dat", "resources.pak",
  ]
}

///|
fn windows_runtime_root_data_files() -> Array[String] {
  windows_runtime_resource_files()
}

///|
fn windows_runtime_required_paths(runtime : String) -> Array[String] {
  let paths : Array[String] = []
  for name in windows_runtime_binary_files() {
    paths.push(resolve_path(runtime, "bin/" + name))
  }
  for name in windows_runtime_root_data_files() {
    paths.push(resolve_path(runtime, "bin/" + name))
  }
  for name in windows_runtime_resource_files() {
    paths.push(resolve_path(runtime, "Resources/" + name))
  }
  paths.push(resolve_path(runtime, "Resources/locales/en-US.pak"))
  paths
}

///|
fn require_windows_runtime_layout(runtime : String) -> Unit raise {
  let missing : Array[String] = []
  for path in windows_runtime_required_paths(runtime) {
    if !path_is_file(path) {
      missing.push(path)
    }
  }
  let locales = resolve_path(runtime, "Resources/locales")
  if !path_is_dir(locales) {
    missing.push(locales)
  }
  if missing.length() > 0 {
    raise WindowsPackagingError::InvalidConfiguration(
      detail="active Windows Proton runtime is incomplete; missing:\n" +
        missing.join("\n"),
    )
  }
}

///|
fn windows_portable_output(plan : PackagePlan) -> String {
  resolve_path(plan.output, package_executable_name(plan.product_name))
}

///|
fn windows_portable_staging(plan : PackagePlan) -> String {
  resolve_path(
    plan.output,
    "." + package_executable_name(plan.product_name) + ".staging",
  )
}

///|
fn windows_archive_path(plan : PackagePlan) -> String {
  resolve_path(plan.output, package_executable_name(plan.product_name) + ".zip")
}

///|
fn windows_archive_staging_path(plan : PackagePlan) -> String {
  resolve_path(
    plan.output,
    "." + package_executable_name(plan.product_name) + ".staging.zip",
  )
}

///|
async fn recover_windows_backup(destination : String, label : String) -> Unit {
  let backup = destination + ".backup"
  guard @mbfs.path_exists(backup) else { return }
  if @mbfs.path_exists(destination) {
    remove_tree(backup)
  } else {
    @async_fs.rename(backup, destination) catch {
      error =>
        raise WindowsPackagingError::ToolFailure(
          stage="restore interrupted " + label,
          detail=backup + ": " + @debug.render(@debug.to_repr(error)),
        )
    }
  }
}

///|
async fn rollback_windows_promotion(
  staging : String,
  destination : String,
  backup : String,
  label : String,
  primary : Error,
) -> Unit {
  let errors : Array[String] = []
  if @mbfs.path_exists(destination) {
    @async_fs.rename(destination, staging) catch {
      error =>
        errors.push(
          "failed to move the promoted " +
          label +
          " aside: " +
          @debug.render(@debug.to_repr(error)),
        )
    }
  }
  if @mbfs.path_exists(backup) && !@mbfs.path_exists(destination) {
    @async_fs.rename(backup, destination) catch {
      error =>
        errors.push(
          "failed to restore the previous " +
          label +
          ": " +
          @debug.render(@debug.to_repr(error)),
        )
    }
  }
  remove_tree(staging) catch {
    error =>
      errors.push(
        "failed to clean rolled-back " +
        label +
        " staging: " +
        error.to_string(),
      )
  }
  if errors.length() > 0 {
    raise WindowsPackagingError::ToolFailure(
      stage=label + " rollback",
      detail=primary.to_string() +
        "; rollback/cleanup also failed: " +
        errors.join("; "),
    )
  } else {
    raise primary
  }
}

///|
async fn promote_windows_artifact(
  staging : String,
  destination : String,
  label : String,
) -> Unit {
  recover_windows_backup(destination, label)
  let backup = destination + ".backup"
  let had_destination = @mbfs.path_exists(destination)
  if had_destination {
    @async_fs.rename(destination, backup) catch {
      error =>
        raise WindowsPackagingError::ToolFailure(
          stage="preserve existing " + label,
          detail=@debug.render(@debug.to_repr(error)),
        )
    }
  }
  @async_fs.rename(staging, destination) catch {
    error => {
      let primary : Error = WindowsPackagingError::ToolFailure(
        stage="promote staged " + label,
        detail=@debug.render(@debug.to_repr(error)),
      )
      if had_destination {
        @async_fs.rename(backup, destination) catch {
          rollback_error =>
            raise WindowsPackagingError::ToolFailure(
              stage=label + " rollback",
              detail=primary.to_string() +
                "; rollback also failed and the previous artifact remains at " +
                backup +
                ": " +
                @debug.render(@debug.to_repr(rollback_error)),
            )
        }
      }
      raise primary
    }
  }
  remove_tree(backup) catch {
    error =>
      rollback_windows_promotion(
        staging,
        destination,
        backup,
        label,
        WindowsPackagingError::ToolFailure(
          stage=label + " backup cleanup",
          detail=backup + ": " + error.to_string(),
        ),
      )
  }
}

///|
async fn prepare_windows_package_paths(plan : PackagePlan) -> Unit {
  ensure_dir(plan.output)
  recover_windows_backup(windows_portable_output(plan), "Windows app")
  remove_tree(windows_portable_staging(plan))
  if plan.targets.contains("zip") {
    recover_windows_backup(windows_archive_path(plan), "Windows zip")
    remove_tree(windows_archive_staging_path(plan))
  }
  ()
}

///|
async fn cleanup_failed_windows_package(plan : PackagePlan) -> Unit {
  let errors : Array[String] = []
  remove_tree(windows_portable_staging(plan)) catch {
    error => errors.push(error.to_string())
  }
  recover_windows_backup(windows_portable_output(plan), "Windows app") catch {
    error => errors.push(error.to_string())
  }
  remove_tree(windows_archive_staging_path(plan)) catch {
    error => errors.push(error.to_string())
  }
  recover_windows_backup(windows_archive_path(plan), "Windows zip") catch {
    error => errors.push(error.to_string())
  }
  if errors.length() > 0 {
    raise WindowsPackagingError::ToolFailure(
      stage="Windows package cleanup",
      detail=errors.join("; "),
    )
  }
}

///|
async fn stage_windows_portable(
  plan : PackagePlan,
  executable : String,
  runtime : String,
) -> Unit {
  stage_windows_portable_with_options(
    plan,
    executable,
    runtime,
    default_windows_sign_tool(),
    None,
    true,
  )
}

///|
async fn stage_windows_portable_with_options(
  plan : PackagePlan,
  executable : String,
  runtime : String,
  sign_tool : WindowsSignTool,
  signing : WindowsSigningConfig?,
  announce : Bool,
) -> Unit {
  prepare_windows_package_paths(plan)
  stage_windows_portable_impl(
    plan, executable, runtime, sign_tool, signing, announce,
  ) catch {
    error => {
      cleanup_failed_windows_package(plan) catch {
        cleanup_error =>
          raise WindowsPackagingError::ToolFailure(
            stage="Windows package rollback/cleanup",
            detail=error.to_string() + "; " + cleanup_error.to_string(),
          )
      }
      raise error
    }
  }
}

///|
async fn stage_windows_portable_impl(
  plan : PackagePlan,
  executable : String,
  runtime : String,
  sign_tool : WindowsSignTool,
  signing : WindowsSigningConfig?,
  announce : Bool,
) -> Unit {
  require_windows_runtime_layout(runtime)
  guard path_is_file(executable) else {
    raise WindowsPackagingError::MissingTarget(path=executable)
  }
  let staging = windows_portable_staging(plan)
  ensure_dir(staging)
  for name in windows_runtime_binary_files() {
    copy_file(resolve_path(runtime, "bin/" + name), resolve_path(staging, name))
  }
  for name in windows_runtime_root_data_files() {
    copy_file(resolve_path(runtime, "bin/" + name), resolve_path(staging, name))
  }
  copy_tree(
    resolve_path(runtime, "Resources"),
    resolve_path(staging, "Resources"),
  )
  copy_file(
    executable,
    resolve_path(staging, package_executable_name(plan.product_name) + ".exe"),
  )
  copy_file(plan.config_path, resolve_path(staging, "moon.proton"))
  stage_project_inputs(plan, staging)
  write_package_manifest(plan, staging, "windows-portable")
  validate_windows_portable_layout(plan, staging)
  if plan.sign {
    match signing {
      Some(signing) =>
        sign_windows_portable_configured(plan, staging, sign_tool, signing)
      None => sign_windows_portable_with_tool(plan, staging, sign_tool)
    }
  }
  let output = windows_portable_output(plan)
  promote_windows_artifact(staging, output, "Windows app")
  if announce {
    println("Packaged Windows portable app: " + output)
  }
  if plan.targets.contains("zip") {
    create_windows_zip(plan, output, announce)
  }
  ()
}

///|
fn validate_windows_portable_layout(
  plan : PackagePlan,
  output : String,
) -> Unit raise {
  let required : Array[String] = [
    resolve_path(output, package_executable_name(plan.product_name) + ".exe"),
    resolve_path(output, "moon.proton"),
    resolve_path(output, "proton-package.json"),
  ]
  for name in windows_runtime_binary_files() {
    required.push(resolve_path(output, name))
  }
  for name in windows_runtime_root_data_files() {
    required.push(resolve_path(output, name))
  }
  for name in windows_runtime_resource_files() {
    required.push(resolve_path(output, "Resources/" + name))
  }
  required.push(resolve_path(output, "Resources/locales/en-US.pak"))
  let missing : Array[String] = []
  for path in required {
    if !path_is_file(path) {
      missing.push(path)
    }
  }
  let locales = resolve_path(output, "Resources/locales")
  if !path_is_dir(locales) {
    missing.push(locales)
  }
  if missing.length() > 0 {
    raise WindowsPackagingError::Verification(
      detail="staged portable layout is incomplete; missing:\n" +
        missing.join("\n"),
    )
  }
  for
    forbidden in [
      "proton.lib", "libcef.lib", "bootstrap.exe", "bootstrapc.exe", "bin",
    ] {
    let path = resolve_path(output, forbidden)
    if @mbfs.path_exists(path) {
      raise WindowsPackagingError::Verification(
        detail="staged portable layout contains a build-only or sample artifact: " +
          path,
      )
    }
  }
  ()
}

///|
fn windows_owned_sign_targets(
  plan : PackagePlan,
  output : String,
) -> Array[String] {
  [
    resolve_path(output, package_executable_name(plan.product_name) + ".exe"),
    resolve_path(output, "cef_process.exe"),
    resolve_path(output, "proton.dll"),
  ]
}

///|
fn windows_upstream_signature_targets(output : String) -> Array[String] {
  [resolve_path(output, "d3dcompiler_47.dll"), resolve_path(output, "dxil.dll")]
}

///|
fn windows_timestamp_url(value : String?) -> String? {
  match value {
    None => Some(windows_default_timestamp_url)
    Some(value) => {
      let value = value.trim().to_owned()
      if value == "" || value.to_lower() == "none" {
        None
      } else {
        Some(value)
      }
    }
  }
}

///|
fn windows_signtool_sign_args(
  certificate : String,
  password : String,
  timestamp : String?,
  target : String,
) -> Array[String] {
  let args : Array[String] = ["sign", "/fd", "SHA256", "/f", certificate]
  if password != "" {
    args.push("/p")
    args.push(password)
  }
  match timestamp {
    Some(timestamp) => {
      args.push("/tr")
      args.push(timestamp)
      args.push("/td")
      args.push("SHA256")
    }
    None => ()
  }
  args.push(target)
  args
}

///|
fn windows_signtool_verify_args(target : String) -> Array[String] {
  ["verify", "/pa", "/all", "/v", target]
}

///|
async fn run_windows_signtool(
  tool : WindowsSignTool,
  args : Array[String],
  action : String,
  target : String,
) -> Unit {
  let command_args = copy_strings(tool.prefix_args)
  for arg in args {
    command_args.push(arg)
  }
  let (code, _) = @process.collect_output_merged(
    tool.executable,
    command_args,
    no_console_window=true,
  ) catch {
    _ =>
      raise WindowsPackagingError::ToolFailure(
        stage="signtool " + action,
        detail=target,
      )
  }
  if code != 0 {
    raise WindowsPackagingError::ToolFailure(
      stage="signtool " + action,
      detail="exit code " + code.to_string() + ": " + target,
    )
  }
}

///|
async fn verify_windows_signature_with_tool(
  tool : WindowsSignTool,
  target : String,
  label : String,
) -> Unit {
  guard path_is_file(target) else {
    raise WindowsPackagingError::MissingTarget(path=target)
  }
  run_windows_signtool(
    tool,
    windows_signtool_verify_args(target),
    "verify " + label,
    target,
  )
}

///|
async fn sign_windows_portable_with_tool(
  plan : PackagePlan,
  output : String,
  tool : WindowsSignTool,
) -> Unit {
  let signing = windows_signing_config_from_env()
  sign_windows_portable_configured(plan, output, tool, signing)
}

///|
fn windows_signing_config_from_env() -> WindowsSigningConfig raise WindowsPackagingError {
  let certificate = match @sys.get_env_var("PROTON_WINDOWS_CERTIFICATE") {
    Some(path) if path.trim().to_owned() != "" => path.trim().to_owned()
    _ =>
      raise InvalidConfiguration(
        detail="--sign requires PROTON_WINDOWS_CERTIFICATE on Windows",
      )
  }
  guard path_is_file(certificate) else {
    raise InvalidConfiguration(
      detail="Windows signing certificate is missing: " + certificate,
    )
  }
  let password = @sys.get_env_var("PROTON_WINDOWS_CERTIFICATE_PASSWORD").unwrap_or(
    "",
  )
  let timestamp = windows_timestamp_url(
    @sys.get_env_var("PROTON_WINDOWS_TIMESTAMP_URL"),
  )
  WindowsSigningConfig::{ certificate, password, timestamp }
}

///|
async fn sign_windows_portable_configured(
  plan : PackagePlan,
  output : String,
  tool : WindowsSignTool,
  signing : WindowsSigningConfig,
) -> Unit {
  guard path_is_file(signing.certificate) else {
    raise WindowsPackagingError::InvalidConfiguration(
      detail="Windows signing certificate is missing: " + signing.certificate,
    )
  }
  let owned_targets = windows_owned_sign_targets(plan, output)
  for target in owned_targets {
    guard path_is_file(target) else {
      raise WindowsPackagingError::MissingTarget(path=target)
    }
  }
  for target in owned_targets {
    run_windows_signtool(
      tool,
      windows_signtool_sign_args(
        signing.certificate,
        signing.password,
        signing.timestamp,
        target,
      ),
      "sign",
      target,
    )
    verify_windows_signature_with_tool(tool, target, "Proton-owned signature")
  }
  for target in windows_upstream_signature_targets(output) {
    verify_windows_signature_with_tool(
      tool, target, "upstream Microsoft signature",
    )
  }
  ()
}

///|
async fn create_windows_zip(
  plan : PackagePlan,
  source : String,
  announce : Bool,
) -> Unit {
  let archive = windows_archive_path(plan)
  let staging = windows_archive_staging_path(plan)
  remove_tree(staging)
  let compress_script =
    #|& {
    #|  $ErrorActionPreference = "Stop"
    #|  Compress-Archive -LiteralPath $env:PROTON_PACKAGE_ZIP_SOURCE -DestinationPath $env:PROTON_PACKAGE_ZIP_DESTINATION -Force
    #|}
  let (code, _) = @process.collect_output_merged(
    "powershell",
    ["-NoProfile", "-NonInteractive", "-Command", compress_script],
    extra_env={
      "PROTON_PACKAGE_ZIP_SOURCE": source,
      "PROTON_PACKAGE_ZIP_DESTINATION": staging,
    },
  ) catch {
    _ =>
      raise WindowsPackagingError::ToolFailure(
        stage="create Windows zip",
        detail=staging,
      )
  }
  guard code == 0 else {
    raise WindowsPackagingError::ToolFailure(
      stage="create Windows zip",
      detail="exit code " + code.to_string(),
    )
  }
  let verify_script =
    #|& {
    #|  $ErrorActionPreference = "Stop"
    #|  Add-Type -AssemblyName System.IO.Compression.FileSystem
    #|  $zip = [System.IO.Compression.ZipFile]::OpenRead($env:PROTON_PACKAGE_ZIP_VERIFY)
    #|  try {
    #|    if ($zip.Entries.Count -eq 0) { exit 2 }
    #|  } finally {
    #|    $zip.Dispose()
    #|  }
    #|}
  let (verify_code, _) = @process.collect_output_merged(
    "powershell",
    ["-NoProfile", "-NonInteractive", "-Command", verify_script],
    extra_env={ "PROTON_PACKAGE_ZIP_VERIFY": staging },
  ) catch {
    _ =>
      raise WindowsPackagingError::Verification(
        detail="failed to open " + staging,
      )
  }
  guard verify_code == 0 else {
    raise WindowsPackagingError::Verification(
      detail="zip verification exited with code " +
        verify_code.to_string() +
        ": " +
        staging,
    )
  }
  promote_windows_artifact(staging, archive, "Windows zip")
  if announce {
    println("Created archive: " + archive)
  }
  ()
}
