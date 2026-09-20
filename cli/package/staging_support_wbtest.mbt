///|
fn test_staging_plan(
  root : String,
  sign_binaries? : Array[String] = [],
) -> PackagePlan {
  PackagePlan::{
    root,
    app_package: "app",
    config_path: resolve_path(root, "proton.project.json"),
    product_name: "Demo & App",
    identifier: "dev.proton.demo",
    version: "1.2.3",
    formats: [@packager.PackageFormat::App],
    output: resolve_path(root, "dist"),
    base_dir: root,
    update_revision: 42UL,
    frontend_dist: None,
    resources: [],
    sign_binaries,
    release: true,
    prepare: None,
    icons: [],
    url_schemes: [],
    document_types: [],
    nsis_install_mode: @packager.NsisInstallMode::CurrentUser,
    sign: false,
    notarize: false,
  }
}

///|
test "resolved runtime platform selects the Proton package layout" {
  assert_true(staging_host_from_platform("darwin-arm64") == Macos)
  assert_true(staging_host_from_platform("win32-x64") == Windows)
  assert_true(staging_host_from_platform("linux-x64") == Linux)
  try ignore(staging_host_from_platform("freebsd-x64")) catch {
    StagingRuntimeError::UnsupportedPlatform(platform~) =>
      assert_eq(platform, "freebsd-x64")
    _ => abort("expected an unsupported platform error")
  } noraise {
    _ => abort("expected an unsupported platform error")
  }
}

///|
test "macOS bundle defines the complete CEF helper family" {
  let helpers = macos_helper_specs("Demo & App", "dev.proton.demo")
  @debug.assert_eq(helpers.map(fn(helper) { helper.bundle_name }), [
    "Demo & App Helper", "Demo & App Helper (Alerts)", "Demo & App Helper (GPU)",
    "Demo & App Helper (Plugin)", "Demo & App Helper (Renderer)",
  ])
  @debug.assert_eq(helpers.map(fn(helper) { helper.bundle_identifier }), [
    "dev.proton.demo.helper", "dev.proton.demo.helper.alerts", "dev.proton.demo.helper.gpu",
    "dev.proton.demo.helper.plugin", "dev.proton.demo.helper.renderer",
  ])
  for helper in helpers {
    assert_eq(helper.executable_name, helper.bundle_name)
  }
}

///|
test "macOS helper plist matches its bundle identity" {
  let spec = test_staging_plan(".")
  let helper = macos_helper_specs(spec.product_name, spec.identifier)[4]
  let plist = helper_info_plist(spec, helper)
  assert_true(
    plist.contains(
      "<key>CFBundleExecutable</key><string>Demo &amp; App Helper (Renderer)</string>",
    ),
  )
  assert_true(
    plist.contains(
      "<key>CFBundleIdentifier</key><string>dev.proton.demo.helper.renderer</string>",
    ),
  )
  assert_true(
    plist.contains("<key>CFBundleVersion</key><string>1.2.3</string>"),
  )
}

///|
test "thin Mach-O headers expose their filetype" {
  let executable = b"\xcf\xfa\xed\xfe\x0c\x00\x00\x01\x00\x00\x00\x00\x02\x00\x00\x00"
  let dsym = b"\xcf\xfa\xed\xfe\x0c\x00\x00\x01\x00\x00\x00\x00\x0a\x00\x00\x00"
  let thin32 = b"\xce\xfa\xed\xfe\x0c\x00\x00\x00\x00\x00\x00\x00\x06\x00\x00\x00"
  assert_eq(macho_thin_filetype(executable), Some(0x2))
  assert_eq(macho_thin_filetype(dsym), Some(0xa))
  assert_eq(macho_thin_filetype(thin32), Some(0x6))
}

///|
test "unrecognized executable formats are not rejected as Mach-O" {
  let fat = b"\xca\xfe\xba\xbe\x00\x00\x00\x02\x01\x00\x00\x0c\x00\x00\x00\x00"
  assert_eq(macho_thin_filetype(fat), None)
  assert_eq(macho_thin_filetype(b"#!/bin/sh\necho hi\n"), None)
  assert_eq(macho_thin_filetype(b"\xcf\xfa\xed\xfe"), None)
}

///|
test "Mach-O rejection reports the discovered filetype" {
  inspect(
    StagingPlanError::NotLaunchableMachO(
      path="SeekMoon.app/Contents/MacOS/seekmoon",
      filetype=0xa,
    ).message(),
    content="bundle executable SeekMoon.app/Contents/MacOS/seekmoon is a Mach-O of type MH_DSYM, not MH_EXECUTE",
  )
}

///|
