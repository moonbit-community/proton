///|
fn windows_test_spec(
  root : String,
  targets : Array[String],
  sign : Bool,
) -> ProtonBundleSpec {
  let package_spec = @packager.PackageSpec(
    resolve_path(root, "app.exe"),
    "Demo App",
    "dev.proton.demo",
    "1.0.0",
    targets.map(target => {
      match target {
        "app" => @packager.PackageFormat::App
        "zip" => @packager.PackageFormat::Zip
        _ => abort("unsupported test target")
      }
    }),
    resolve_path(root, "output with spaces"),
    sign~,
  )
  ProtonBundleSpec::{
    package_spec,
    base_dir: root,
    update_revision: 0UL,
    frontend_dist: Some(resolve_path(root, "frontend/dist")),
    resources: [resolve_path(root, "bundle resources/**")],
    sign_binaries: [],
  }
}

///|
test "Windows signing includes configured resource binaries" {
  let root = "fixtures/proton-package-windows-configured-signing"
  let spec = windows_test_spec(root, ["app"], true)
  spec.sign_binaries.push(resolve_path(root, "helpers/worker.exe"))
  assert_true(
    windows_package_sign_targets(spec).contains("Resources/helpers/worker.exe"),
  )
}

///|
test "Windows signing rejects binaries outside the project" {
  let spec = windows_test_spec("/tmp/proton-package", ["app"], true)
  spec.sign_binaries.push("/tmp/worker.exe")
  try ignore(windows_package_sign_targets(spec)) catch {
    BundlePlanError::InputOutsideBase(path="/tmp/worker.exe") => ()
    _ => abort("expected an outside-project error")
  } noraise {
    _ => abort("expected the signing target to be rejected")
  }
}
