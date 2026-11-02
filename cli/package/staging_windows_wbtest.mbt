///|
fn windows_test_spec(
  root : String,
  targets : Array[String],
  sign : Bool,
) -> PackagePlan {
  PackagePlan::{
    ..test_staging_plan(root),
    product_name: "Demo App",
    version: "1.0.0",
    formats: targets.map(target => {
      match target {
        "app" => @packager.PackageFormat::App
        "zip" => @packager.PackageFormat::Zip
        _ => abort("unsupported test target")
      }
    }),
    output: resolve_path(root, "output with spaces"),
    sign,
    frontend_dist: Some(resolve_path(root, "frontend/dist")),
    resources: [resolve_path(root, "bundle resources/**")],
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
test "a shared macOS signing tree only stops signed Windows builds" {
  let root = "fixtures/proton-package-windows-sign-tree"
  let spec = windows_test_spec(root, ["app"], true)
  let tree = resolve_path(root, "payload/**")
  spec.sign_binaries.push(tree)
  assert_eq(windows_package_sign_targets(spec), ["cef_process.exe"])
  reject_windows_sign_globs(spec, Macos)
  reject_windows_sign_globs(PackagePlan::{ ..spec, sign: false, }, Windows)
  try
    reject_windows_sign_globs(PackagePlan::{ ..spec, sign: true, }, Windows)
  catch {
    StagingPlanError::UnsupportedSignGlob(path~) => assert_eq(path, tree)
    _ => fail("expected an unsupported signing glob")
  } noraise {
    _ => fail("expected a signed Windows build to refuse the tree")
  }
}

///|
test "Windows signing rejects binaries outside the project" {
  let spec = windows_test_spec("/tmp/proton-package", ["app"], true)
  spec.sign_binaries.push("/tmp/worker.exe")
  try ignore(windows_package_sign_targets(spec)) catch {
    StagingPlanError::InputOutsideBase(path="/tmp/worker.exe") => ()
    _ => abort("expected an outside-project error")
  } noraise {
    _ => abort("expected the signing target to be rejected")
  }
}
