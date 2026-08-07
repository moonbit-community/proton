///|
fn windows_test_plan(
  root : String,
  targets : Array[String],
  sign : Bool,
) -> PackagePlan {
  PackagePlan::{
    root,
    workspace_root: root,
    build_target_dir: @fsutil.resolve_path(root, "package-build"),
    app_package: "app",
    config_path: @fsutil.resolve_path(root, "moon.proton"),
    product_name: "Demo App",
    identifier: "dev.proton.demo",
    version: "1.0.0",
    macos_version: "1.0.0",
    bundle_version: "1.0.0",
    update_revision: 0UL,
    targets,
    output: @fsutil.resolve_path(root, "output with spaces"),
    build: false,
    release: false,
    base_dir: root,
    frontend_dist: Some(@fsutil.resolve_path(root, "frontend/dist")),
    entry_paths: [@fsutil.resolve_path(root, "frontend/dist/index.html")],
    sign_binaries: [],
    resources: [@fsutil.resolve_path(root, "bundle resources/**")],
    icons: [],
    url_schemes: [],
    document_types: [],
    macos_icon: None,
    sign,
    notarize: false,
  }
}

///|
async fn ensure_windows_test_dir(path : String) -> Unit {
  guard !@mbfs.path_exists(path) else { return }
  let parent = @fsutil.path_parent(path)
  if parent != path && !@mbfs.path_exists(parent) {
    ensure_windows_test_dir(parent)
  }
  ensure_dir(path)
}

///|
async fn write_windows_test_file(path : String, text : String) -> Unit {
  ensure_windows_test_dir(@fsutil.path_parent(path))
  write_text(path, text)
}

///|
async fn prepare_windows_test_inputs(root : String) -> (String, String) {
  remove_tree(root)
  let executable = @fsutil.resolve_path(root, "build output/demo.exe")
  let config = @fsutil.resolve_path(root, "moon.proton")
  for
    item in [
      (executable, "exe"),
      (config, "config"),
      (@fsutil.resolve_path(root, "frontend/dist/index.html"), "frontend"),
      (@fsutil.resolve_path(root, "bundle resources/data.txt"), "resource"),
    ] {
    let (path, text) = item
    write_windows_test_file(path, text)
  }
  (executable, config)
}

///|
async fn prepare_windows_test_runtime(root : String) -> String {
  let runtime = @fsutil.resolve_path(root, "runtime files")
  for name in windows_runtime_binary_files() {
    write_windows_test_file(@fsutil.resolve_path(runtime, "bin/" + name), name)
  }
  for name in windows_runtime_root_data_files() {
    write_windows_test_file(@fsutil.resolve_path(runtime, "bin/" + name), name)
  }
  for name in windows_runtime_resource_files() {
    write_windows_test_file(
      @fsutil.resolve_path(runtime, "Resources/" + name),
      name,
    )
  }
  for locale in ["en-US.pak", "fr.pak"] {
    write_windows_test_file(
      @fsutil.resolve_path(runtime, "Resources/locales/" + locale),
      locale,
    )
  }
  for
    extra in [
      "bin/libcef.lib", "bin/bootstrap.exe", "bin/bootstrapc.exe", "lib/proton.lib",
    ] {
    write_windows_test_file(@fsutil.resolve_path(runtime, extra), "build-only")
  }
  runtime
}

///|
async fn windows_test_sign_tool(
  root : String,
  mode : String,
) -> WindowsSignTool {
  let script = @fsutil.resolve_path(root, "fake signtool.ps1")
  let text =
    #|$mode = "{{MODE}}"
    #|$kind = if ($args.Count -gt 0) { $args[0] } else { "" }
    #|if ($env:PROTON_TEST_SIGNTOOL_LOG) {
    #|  Add-Content -LiteralPath $env:PROTON_TEST_SIGNTOOL_LOG -Value ($args -join "|")
    #|}
    #|if (($mode -eq "sign-fail") -and ($kind -eq "sign")) { exit 7 }
    #|if (($mode -eq "verify-fail") -and ($kind -eq "verify")) { exit 8 }
    #|exit 0
  let text = text.replace_all(old="{{MODE}}", new=mode)
  write_windows_test_file(script, text)
  {
    executable: "powershell",
    prefix_args: [
      "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script,
    ],
  }
}

///|
test "Windows signtool args use SHA-256 and RFC3161 timestamp" {
  @debug.assert_eq(
    windows_signtool_sign_args(
      "certificate.pfx",
      "secret",
      Some("https://timestamp.example.test"),
      "Demo App.exe",
    ),
    [
      "sign", "/fd", "SHA256", "/f", "certificate.pfx", "/p", "secret", "/tr", "https://timestamp.example.test",
      "/td", "SHA256", "Demo App.exe",
    ],
  )
  @debug.assert_eq(
    windows_signtool_sign_args("certificate.pfx", "", None, "Demo App.exe"),
    ["sign", "/fd", "SHA256", "/f", "certificate.pfx", "Demo App.exe"],
  )
  @debug.assert_eq(windows_signtool_verify_args("Demo App.exe"), [
    "verify", "/pa", "/all", "/v", "Demo App.exe",
  ])
  @debug.assert_eq(
    windows_timestamp_url(None),
    Some(windows_default_timestamp_url),
  )
  @debug.assert_eq(windows_timestamp_url(Some("none")), None)
  @debug.assert_eq(windows_timestamp_url(Some("  ")), None)
}

///|
test "Windows signing includes configured resource binaries" {
  let root = "target/proton-package-windows-configured-signing"
  let plan = windows_test_plan(root, ["app"], true)
  plan.sign_binaries.push(@fsutil.resolve_path(root, "helpers/worker.exe"))
  let output = @fsutil.resolve_path(root, "portable")
  assert_true(
    windows_owned_sign_targets(plan, output).contains(
      @fsutil.resolve_path(output, "helpers/worker.exe"),
    ),
  )
}

///|
#cfg(platform="windows")
async test "Windows signtool signs and verifies configured resource binaries" {
  let root = "target/proton-package-windows-configured-signtool"
  remove_tree(root)
  let output = @fsutil.resolve_path(root, "portable")
  let plan = windows_test_plan(root, ["app"], true)
  let binary = @fsutil.resolve_path(root, "helpers/worker.exe")
  plan.sign_binaries.push(binary)
  for target in windows_owned_sign_targets(plan, output) {
    write_windows_test_file(target, "binary")
  }
  for target in windows_upstream_signature_targets(output) {
    write_windows_test_file(target, "upstream")
  }
  let certificate = @fsutil.resolve_path(root, "test certificate.pfx")
  write_windows_test_file(certificate, "certificate")
  let log = @fsutil.resolve_path(root, "signtool.log")
  let old_log = @env.get_env_var("PROTON_TEST_SIGNTOOL_LOG")
  @env.set_env_var("PROTON_TEST_SIGNTOOL_LOG", log)
  defer restore_package_env("PROTON_TEST_SIGNTOOL_LOG", old_log)
  sign_windows_portable_configured(
    plan,
    output,
    windows_test_sign_tool(root, "success"),
    WindowsSigningConfig::{ certificate, password: "", timestamp: None },
  )
  let text = @async_fs.read_file(log).text()
  assert_true(
    text.contains(
      "sign|/fd|SHA256|/f|" +
      certificate +
      "|" +
      @fsutil.resolve_path(output, "helpers/worker.exe"),
    ),
  )
  assert_true(
    text.contains(
      "verify|/pa|/all|/v|" + @fsutil.resolve_path(output, "helpers/worker.exe"),
    ),
  )
}

///|
async test "Windows icon selection accepts ico and rejects a missing source" {
  let root = "target/proton-package-windows-icon"
  remove_tree(root)
  let selected = @fsutil.resolve_path(root, "Demo.ICO")
  assert_eq(
    first_windows_icon(["icons/icon.png", selected, "icons/fallback.ico"]),
    Some(selected),
  )
  assert_eq(first_windows_icon(["icons/icon.png", "icons/icon.icns"]), None)
  let plan = windows_test_plan(root, ["app"], false)
  plan.icons.push(selected)
  try stage_windows_icon(plan, @fsutil.resolve_path(root, "demo.exe")) catch {
    PackagePlanError::MissingIcon(path~) => assert_eq(path, selected)
    _ => abort("expected missing Windows icon")
  } noraise {
    _ => abort("expected missing Windows icon failure")
  }
}

///|
test "Windows path resolution keeps dotted relative children under the base" {
  let path = normalize_slashes(
    @fsutil.resolve_path("target/proton-path-base", ".proton/runtime.json"),
  )
  assert_true(path.has_suffix("/target/proton-path-base/.proton/runtime.json"))
}

///|
async test "Windows runtime validation rejects a missing required file" {
  let root = "target/proton-package-windows-missing-runtime"
  ignore(prepare_windows_test_inputs(root))
  let runtime = prepare_windows_test_runtime(root)
  let missing = @fsutil.resolve_path(runtime, "bin/chrome_elf.dll")
  remove_tree(missing)
  try require_windows_runtime_layout(runtime) catch {
    WindowsPackagingError::InvalidConfiguration(detail~) => {
      assert_true(
        detail.contains("active Windows Proton runtime is incomplete"),
      )
      assert_true(detail.contains(missing))
    }
    _ => abort("expected incomplete Windows runtime")
  } noraise {
    _ => abort("expected missing Windows runtime failure")
  }
}

///|
async test "Windows portable staging is atomic and excludes build artifacts" {
  let root = "target/proton package windows layout with spaces"
  let (executable, _) = prepare_windows_test_inputs(root)
  let runtime = prepare_windows_test_runtime(root)
  let plan = windows_test_plan(root, ["app"], false)
  let output = windows_portable_output(plan)
  ensure_dir(output)
  write_windows_test_file(@fsutil.resolve_path(output, "old.txt"), "old")
  stage_windows_portable_with_options(
    plan,
    executable,
    runtime,
    default_windows_sign_tool(),
    None,
    false,
  )
  for
    required in [
      "demo-app.exe", "proton.dll", "cef_process.exe", "libcef.dll", "icudtl.dat",
      "Resources/icudtl.dat", "Resources/locales/en-US.pak", "moon.proton", "frontend/dist/index.html",
      "bundle resources/data.txt", "proton-package.json",
    ] {
    assert_true(@mbfs.path_exists(@fsutil.resolve_path(output, required)))
  }
  for
    forbidden in [
      "old.txt", "proton.lib", "libcef.lib", "bootstrap.exe", "bootstrapc.exe", "bin",
    ] {
    assert_false(@mbfs.path_exists(@fsutil.resolve_path(output, forbidden)))
  }
  assert_false(@mbfs.path_exists(windows_portable_staging(plan)))
  assert_false(@mbfs.path_exists(output + ".backup"))
}

///|
async test "Windows portable stages a configured signing binary from resources" {
  let root = "target/proton-package-windows-resource-signing"
  let (executable, _) = prepare_windows_test_inputs(root)
  let binary = @fsutil.resolve_path(root, "helpers/worker.exe")
  write_windows_test_file(binary, "worker")
  let runtime = prepare_windows_test_runtime(root)
  let plan = windows_test_plan(root, ["app"], false)
  plan.resources.push(binary)
  plan.sign_binaries.push(binary)
  stage_windows_portable_with_options(
    plan,
    executable,
    runtime,
    default_windows_sign_tool(),
    None,
    false,
  )
  let output = windows_portable_output(plan)
  let staged_binary = @fsutil.resolve_path(output, "helpers/worker.exe")
  assert_true(@fsutil.path_is_file(staged_binary))
  assert_true(windows_owned_sign_targets(plan, output).contains(staged_binary))
}

///|
#cfg(platform="windows")
async test "Windows portable zip is atomic and extracts from paths with spaces" {
  let root = "target/proton-package-windows-zip with spaces"
  let (executable, _) = prepare_windows_test_inputs(root)
  let runtime = prepare_windows_test_runtime(root)
  let plan = windows_test_plan(root, ["app", "zip"], false)
  stage_windows_portable_with_options(
    plan,
    executable,
    runtime,
    default_windows_sign_tool(),
    None,
    false,
  )
  let archive = windows_archive_path(plan)
  assert_true(@fsutil.path_is_file(archive))
  assert_false(@mbfs.path_exists(windows_archive_staging_path(plan)))
  assert_false(@mbfs.path_exists(archive + ".backup"))
  let extracted = @fsutil.resolve_path(root, "extracted archive with spaces")
  let script =
    #|& {
    #|  $ErrorActionPreference = "Stop"
    #|  Expand-Archive -LiteralPath $env:PROTON_TEST_ARCHIVE -DestinationPath $env:PROTON_TEST_EXTRACTED -Force
    #|}
  let (code, _) = @process.collect_output_merged(
    "powershell",
    ["-NoProfile", "-NonInteractive", "-Command", script],
    extra_env={
      "PROTON_TEST_ARCHIVE": archive,
      "PROTON_TEST_EXTRACTED": extracted,
    },
  )
  assert_eq(code, 0)
  assert_true(
    @fsutil.path_is_file(
      @fsutil.resolve_path(extracted, "demo-app/demo-app.exe"),
    ),
  )
}

///|
async test "Windows promotion rolls back when staging is missing" {
  let root = "target/proton-package-windows-rollback"
  remove_tree(root)
  let destination = @fsutil.resolve_path(root, "Demo App")
  let marker = @fsutil.resolve_path(destination, "old.txt")
  write_windows_test_file(marker, "old")
  try
    promote_windows_artifact(
      @fsutil.resolve_path(root, "missing staging"),
      destination,
      "Windows app",
    )
  catch {
    WindowsPackagingError::ToolFailure(stage~, ..) =>
      assert_true(stage.contains("promote staged Windows app"))
    _ => abort("expected Windows promotion failure")
  } noraise {
    _ => abort("expected promotion failure")
  }
  assert_true(@fsutil.path_is_file(marker))
  assert_false(@mbfs.path_exists(destination + ".backup"))
}

///|
async test "Windows promotion restores a stale backup before continuing" {
  let root = "target/proton-package-windows-stale-backup"
  remove_tree(root)
  let destination = @fsutil.resolve_path(root, "Demo App")
  let backup = destination + ".backup"
  let marker = @fsutil.resolve_path(backup, "old.txt")
  write_windows_test_file(marker, "old")
  try
    promote_windows_artifact(
      @fsutil.resolve_path(root, "missing staging"),
      destination,
      "Windows app",
    )
  catch {
    _ => ()
  } noraise {
    _ => abort("expected promotion failure")
  }
  assert_true(
    @fsutil.path_is_file(@fsutil.resolve_path(destination, "old.txt")),
  )
  assert_false(@mbfs.path_exists(backup))
}

///|
async test "Windows signing rejects a missing target before invoking signtool" {
  let root = "target/proton-package-windows-missing-sign-target"
  let (_, _) = prepare_windows_test_inputs(root)
  let output = @fsutil.resolve_path(root, "portable")
  for
    path in [
      @fsutil.resolve_path(output, "demo-app.exe"),
      @fsutil.resolve_path(output, "proton.dll"),
    ] {
    write_windows_test_file(path, "binary")
  }
  let certificate = @fsutil.resolve_path(root, "test certificate.pfx")
  write_windows_test_file(certificate, "certificate")
  try
    sign_windows_portable_configured(
      windows_test_plan(root, ["app"], true),
      output,
      windows_test_sign_tool(root, "success"),
      WindowsSigningConfig::{
        certificate,
        password: "",
        timestamp: Some(windows_default_timestamp_url),
      },
    )
  catch {
    WindowsPackagingError::MissingTarget(path~) =>
      assert_true(path.contains("cef_process.exe"))
    error =>
      abort("expected missing Windows signing target, got " + error.to_string())
  } noraise {
    _ => abort("expected missing signing target failure")
  }
}

///|
#cfg(platform="windows")
async test "Windows signing failure does not leak the certificate password" {
  let root = "target/proton-package-windows-sign-failure"
  let (_, _) = prepare_windows_test_inputs(root)
  let output = @fsutil.resolve_path(root, "portable")
  let plan = windows_test_plan(root, ["app"], true)
  for target in windows_owned_sign_targets(plan, output) {
    write_windows_test_file(target, "binary")
  }
  for target in windows_upstream_signature_targets(output) {
    write_windows_test_file(target, "upstream")
  }
  let certificate = @fsutil.resolve_path(root, "test certificate.pfx")
  write_windows_test_file(certificate, "certificate")
  let password = "do-not-print-this-password"
  try
    sign_windows_portable_configured(
      plan,
      output,
      windows_test_sign_tool(root, "sign-fail"),
      WindowsSigningConfig::{ certificate, password, timestamp: None },
    )
  catch {
    WindowsPackagingError::ToolFailure(stage~, detail~) => {
      assert_true(stage.contains("signtool sign"))
      assert_true(detail.contains("7"))
      assert_false(detail.contains(password))
    }
    _ => abort("expected signtool signing failure")
  } noraise {
    _ => abort("expected signtool signing failure")
  }
}

///|
#cfg(platform="windows")
async test "Windows signing failure blocks promotion" {
  let root = "target/proton-package-windows-sign-promotion-failure"
  let (executable, _) = prepare_windows_test_inputs(root)
  let runtime = prepare_windows_test_runtime(root)
  let plan = windows_test_plan(root, ["app"], true)
  let output = windows_portable_output(plan)
  let marker = @fsutil.resolve_path(output, "old.txt")
  write_windows_test_file(marker, "old")
  let certificate = @fsutil.resolve_path(root, "test certificate.pfx")
  write_windows_test_file(certificate, "certificate")
  try
    stage_windows_portable_with_options(
      plan,
      executable,
      runtime,
      windows_test_sign_tool(root, "sign-fail"),
      Some(WindowsSigningConfig::{ certificate, password: "", timestamp: None }),
      false,
    )
  catch {
    WindowsPackagingError::ToolFailure(stage~, detail~) => {
      assert_true(stage.contains("signtool sign"))
      assert_true(detail.contains("7"))
    }
    _ => abort("expected signtool signing failure")
  } noraise {
    _ => abort("expected signtool signing failure")
  }
  assert_true(@fsutil.path_is_file(marker))
  assert_false(@mbfs.path_exists(windows_portable_staging(plan)))
  assert_false(@mbfs.path_exists(output + ".backup"))
}

///|
#cfg(platform="windows")
async test "Windows signature verification failure blocks promotion" {
  let root = "target/proton-package-windows-verify-failure"
  let (executable, _) = prepare_windows_test_inputs(root)
  let runtime = prepare_windows_test_runtime(root)
  let plan = windows_test_plan(root, ["app"], true)
  let output = windows_portable_output(plan)
  let marker = @fsutil.resolve_path(output, "old.txt")
  write_windows_test_file(marker, "old")
  let certificate = @fsutil.resolve_path(root, "test certificate.pfx")
  write_windows_test_file(certificate, "certificate")
  try
    stage_windows_portable_with_options(
      plan,
      executable,
      runtime,
      windows_test_sign_tool(root, "verify-fail"),
      Some(WindowsSigningConfig::{
        certificate,
        password: "",
        timestamp: Some(windows_default_timestamp_url),
      }),
      false,
    )
  catch {
    WindowsPackagingError::ToolFailure(stage~, detail~) => {
      assert_true(stage.contains("signtool verify Proton-owned signature"))
      assert_true(detail.contains("8"))
    }
    _ => abort("expected signtool verification failure")
  } noraise {
    _ => abort("expected signtool verification failure")
  }
  assert_true(@fsutil.path_is_file(marker))
  assert_false(@mbfs.path_exists(windows_portable_staging(plan)))
  assert_false(@mbfs.path_exists(output + ".backup"))
}
