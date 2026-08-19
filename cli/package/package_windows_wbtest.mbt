///|
fn windows_test_plan(
  root : String,
  targets : Array[String],
  sign : Bool,
) -> PackagePlan {
  PackagePlan::{
    root,
    workspace_root: root,
    app_package: "app",
    config_path: @fsutil.resolve_path(root, "proton.project.json"),
    product_name: "Demo App",
    identifier: "dev.proton.demo",
    version: "1.0.0",
    macos_version: "1.0.0",
    bundle_version: "1.0.0",
    update_revision: 0UL,
    targets,
    output: @fsutil.resolve_path(root, "output with spaces"),
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
  let root = "fixtures/proton-package-windows-configured-signing"
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
#cfg(target="wasm")
test "Windows icon embedding requires the native CLI backend" {
  try embed_windows_icon("demo.exe", "demo.ico") catch {
    WindowsPackagingError::ToolFailure(stage~, detail~) => {
      assert_eq(stage, "embed Windows application icon")
      assert_true(detail.contains("native proton_cli backend"))
    }
    _ => abort("expected unsupported Windows icon embedding")
  } noraise {
    _ => abort("expected unsupported Windows icon embedding")
  }
}

///|
test "Windows path resolution keeps dotted relative children under the base" {
  let path = normalize_slashes(
    @fsutil.resolve_path("fixtures/proton-path-base", ".proton/runtime.json"),
  )
  assert_true(
    path.has_suffix("/fixtures/proton-path-base/.proton/runtime.json"),
  )
}
