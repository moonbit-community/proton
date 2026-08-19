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
test "Windows signing includes configured resource binaries" {
  let root = "fixtures/proton-package-windows-configured-signing"
  let plan = windows_test_plan(root, ["app"], true)
  plan.sign_binaries.push(@fsutil.resolve_path(root, "helpers/worker.exe"))
  assert_true(windows_package_sign_targets(plan).contains("helpers/worker.exe"))
}

///|
test "Windows signing rejects binaries outside the project" {
  let plan = windows_test_plan("/tmp/proton-package", ["app"], true)
  plan.sign_binaries.push("/tmp/worker.exe")
  try ignore(windows_package_sign_targets(plan)) catch {
    PackagePlanError::InputOutsideProject(path="/tmp/worker.exe") => ()
    _ => abort("expected an outside-project error")
  } noraise {
    _ => abort("expected the signing target to be rejected")
  }
}
