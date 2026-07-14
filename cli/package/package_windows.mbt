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
fn require_windows_runtime_layout(
  runtime : String,
) -> Result[Unit, PackageError] {
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
    Err(
      CommandError(
        "active Windows Proton runtime is incomplete; missing:\n" +
        missing.join("\n"),
      ),
    )
  } else {
    Ok(())
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
fn package_error_text(error : PackageError) -> String {
  match error {
    UsageError(message, _) | CommandError(message) => message
  }
}

///|
fn combine_package_errors(
  primary : PackageError,
  secondary : PackageError,
  label : String,
) -> PackageError {
  CommandError(
    package_error_text(primary) +
    "; " +
    label +
    ": " +
    package_error_text(secondary),
  )
}

///|
async fn recover_windows_backup(
  destination : String,
  label : String,
) -> Result[Unit, PackageError] {
  let backup = destination + ".backup"
  guard @mbfs.path_exists(backup) else { return Ok(()) }
  if @mbfs.path_exists(destination) {
    match remove_tree(backup) {
      Ok(_) => Ok(())
      Err(error) =>
        Err(
          CommandError(
            "failed to remove stale " +
            label +
            " backup " +
            backup +
            ": " +
            package_error_text(error),
          ),
        )
    }
  } else {
    @async_fs.rename(backup, destination) catch {
      error =>
        return Err(
          CommandError(
            "failed to restore interrupted " +
            label +
            " promotion from " +
            backup +
            ": " +
            @debug.render(@debug.to_repr(error)),
          ),
        )
    }
    Ok(())
  }
}

///|
async fn rollback_windows_promotion(
  staging : String,
  destination : String,
  backup : String,
  label : String,
  primary : PackageError,
) -> Result[Unit, PackageError] {
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
  match remove_tree(staging) {
    Err(error) =>
      errors.push(
        "failed to clean rolled-back " +
        label +
        " staging: " +
        package_error_text(error),
      )
    Ok(_) => ()
  }
  if errors.length() > 0 {
    Err(
      CommandError(
        package_error_text(primary) +
        "; rollback/cleanup also failed: " +
        errors.join("; "),
      ),
    )
  } else {
    Err(primary)
  }
}

///|
async fn promote_windows_artifact(
  staging : String,
  destination : String,
  label : String,
) -> Result[Unit, PackageError] {
  match recover_windows_backup(destination, label) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let backup = destination + ".backup"
  let had_destination = @mbfs.path_exists(destination)
  if had_destination {
    @async_fs.rename(destination, backup) catch {
      error =>
        return Err(
          CommandError(
            "failed to preserve existing " +
            label +
            ": " +
            @debug.render(@debug.to_repr(error)),
          ),
        )
    }
  }
  @async_fs.rename(staging, destination) catch {
    error => {
      let primary = CommandError(
        "failed to promote staged " +
        label +
        ": " +
        @debug.render(@debug.to_repr(error)),
      )
      if had_destination {
        @async_fs.rename(backup, destination) catch {
          rollback_error =>
            return Err(
              CommandError(
                package_error_text(primary) +
                "; rollback also failed and the previous artifact remains at " +
                backup +
                ": " +
                @debug.render(@debug.to_repr(rollback_error)),
              ),
            )
        }
      }
      return Err(primary)
    }
  }
  match remove_tree(backup) {
    Ok(_) => Ok(())
    Err(error) =>
      rollback_windows_promotion(
        staging,
        destination,
        backup,
        label,
        CommandError(
          label +
          " was promoted but its backup could not be removed: " +
          backup +
          ": " +
          package_error_text(error),
        ),
      )
  }
}

///|
async fn prepare_windows_package_paths(
  plan : PackagePlan,
) -> Result[Unit, PackageError] {
  match ensure_dir(plan.output) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match recover_windows_backup(windows_portable_output(plan), "Windows app") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match remove_tree(windows_portable_staging(plan)) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if plan.targets.contains("zip") {
    match recover_windows_backup(windows_archive_path(plan), "Windows zip") {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match remove_tree(windows_archive_staging_path(plan)) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
async fn cleanup_failed_windows_package(
  plan : PackagePlan,
) -> Result[Unit, PackageError] {
  let errors : Array[String] = []
  match remove_tree(windows_portable_staging(plan)) {
    Err(error) => errors.push(package_error_text(error))
    Ok(_) => ()
  }
  match recover_windows_backup(windows_portable_output(plan), "Windows app") {
    Err(error) => errors.push(package_error_text(error))
    Ok(_) => ()
  }
  match remove_tree(windows_archive_staging_path(plan)) {
    Err(error) => errors.push(package_error_text(error))
    Ok(_) => ()
  }
  match recover_windows_backup(windows_archive_path(plan), "Windows zip") {
    Err(error) => errors.push(package_error_text(error))
    Ok(_) => ()
  }
  if errors.length() > 0 {
    Err(CommandError(errors.join("; ")))
  } else {
    Ok(())
  }
}

///|
async fn stage_windows_portable(
  plan : PackagePlan,
  executable : String,
  runtime : String,
) -> Result[Unit, PackageError] {
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
) -> Result[Unit, PackageError] {
  match prepare_windows_package_paths(plan) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let result = stage_windows_portable_impl(
    plan, executable, runtime, sign_tool, signing, announce,
  )
  match result {
    Ok(_) => Ok(())
    Err(error) =>
      match cleanup_failed_windows_package(plan) {
        Ok(_) => Err(error)
        Err(cleanup_error) =>
          Err(
            combine_package_errors(
              error, cleanup_error, "Windows package rollback/cleanup failed",
            ),
          )
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
) -> Result[Unit, PackageError] {
  match require_windows_runtime_layout(runtime) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  guard path_is_file(executable) else {
    return Err(
      CommandError("package release executable is missing: " + executable),
    )
  }
  let staging = windows_portable_staging(plan)
  match ensure_dir(staging) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  for name in windows_runtime_binary_files() {
    match
      copy_file(
        resolve_path(runtime, "bin/" + name),
        resolve_path(staging, name),
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  for name in windows_runtime_root_data_files() {
    match
      copy_file(
        resolve_path(runtime, "bin/" + name),
        resolve_path(staging, name),
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  match
    copy_tree(
      resolve_path(runtime, "Resources"),
      resolve_path(staging, "Resources"),
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match
    copy_file(
      executable,
      resolve_path(staging, package_executable_name(plan.product_name) + ".exe"),
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match copy_file(plan.config_path, resolve_path(staging, "moon.proton")) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match stage_project_inputs(plan, staging) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match write_package_manifest(plan, staging, "windows-portable") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match validate_windows_portable_layout(plan, staging) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if plan.sign {
    let result = match signing {
      Some(signing) =>
        sign_windows_portable_configured(plan, staging, sign_tool, signing)
      None => sign_windows_portable_with_tool(plan, staging, sign_tool)
    }
    match result {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  let output = windows_portable_output(plan)
  match promote_windows_artifact(staging, output, "Windows app") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if announce {
    println("Packaged Windows portable app: " + output)
  }
  if plan.targets.contains("zip") {
    match create_windows_zip(plan, output, announce) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
fn validate_windows_portable_layout(
  plan : PackagePlan,
  output : String,
) -> Result[Unit, PackageError] {
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
    return Err(
      CommandError(
        "staged Windows portable layout is incomplete; missing:\n" +
        missing.join("\n"),
      ),
    )
  }
  for
    forbidden in [
      "proton.lib", "libcef.lib", "bootstrap.exe", "bootstrapc.exe", "bin",
    ] {
    let path = resolve_path(output, forbidden)
    if @mbfs.path_exists(path) {
      return Err(
        CommandError(
          "staged Windows portable layout contains a build-only or sample artifact: " +
          path,
        ),
      )
    }
  }
  Ok(())
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
) -> Result[Unit, PackageError] {
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
      return Err(
        CommandError("failed to run signtool to " + action + ": " + target),
      )
  }
  if code == 0 {
    Ok(())
  } else {
    Err(
      CommandError(
        "signtool " +
        action +
        " exited with code " +
        code.to_string() +
        ": " +
        target,
      ),
    )
  }
}

///|
async fn verify_windows_signature_with_tool(
  tool : WindowsSignTool,
  target : String,
  label : String,
) -> Result[Unit, PackageError] {
  guard path_is_file(target) else {
    return Err(CommandError("required " + label + " is missing: " + target))
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
) -> Result[Unit, PackageError] {
  let signing = match windows_signing_config_from_env() {
    Err(error) => return Err(error)
    Ok(signing) => signing
  }
  sign_windows_portable_configured(plan, output, tool, signing)
}

///|
fn windows_signing_config_from_env() -> Result[
  WindowsSigningConfig,
  PackageError,
] {
  let certificate = match @sys.get_env_var("PROTON_WINDOWS_CERTIFICATE") {
    Some(path) if path.trim().to_owned() != "" => path.trim().to_owned()
    _ =>
      return Err(
        CommandError("--sign requires PROTON_WINDOWS_CERTIFICATE on Windows"),
      )
  }
  guard path_is_file(certificate) else {
    return Err(
      CommandError("Windows signing certificate is missing: " + certificate),
    )
  }
  let password = @sys.get_env_var("PROTON_WINDOWS_CERTIFICATE_PASSWORD").unwrap_or(
    "",
  )
  let timestamp = windows_timestamp_url(
    @sys.get_env_var("PROTON_WINDOWS_TIMESTAMP_URL"),
  )
  Ok(WindowsSigningConfig::{ certificate, password, timestamp })
}

///|
async fn sign_windows_portable_configured(
  plan : PackagePlan,
  output : String,
  tool : WindowsSignTool,
  signing : WindowsSigningConfig,
) -> Result[Unit, PackageError] {
  guard path_is_file(signing.certificate) else {
    return Err(
      CommandError(
        "Windows signing certificate is missing: " + signing.certificate,
      ),
    )
  }
  let owned_targets = windows_owned_sign_targets(plan, output)
  for target in owned_targets {
    guard path_is_file(target) else {
      return Err(
        CommandError("required Windows signing target is missing: " + target),
      )
    }
  }
  for target in owned_targets {
    match
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
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match
      verify_windows_signature_with_tool(tool, target, "Proton-owned signature") {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  for target in windows_upstream_signature_targets(output) {
    match
      verify_windows_signature_with_tool(
        tool, target, "upstream Microsoft signature",
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
async fn create_windows_zip(
  plan : PackagePlan,
  source : String,
  announce : Bool,
) -> Result[Unit, PackageError] {
  let archive = windows_archive_path(plan)
  let staging = windows_archive_staging_path(plan)
  match remove_tree(staging) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
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
    _ => return Err(CommandError("failed to create Windows zip: " + staging))
  }
  guard code == 0 else {
    return Err(
      CommandError("Windows zip command exited with code " + code.to_string()),
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
    _ => return Err(CommandError("failed to verify Windows zip: " + staging))
  }
  guard verify_code == 0 else {
    return Err(
      CommandError(
        "Windows zip verification exited with code " +
        verify_code.to_string() +
        ": " +
        staging,
      ),
    )
  }
  match promote_windows_artifact(staging, archive, "Windows zip") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if announce {
    println("Created archive: " + archive)
  }
  Ok(())
}
