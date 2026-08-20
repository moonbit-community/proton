///|
fn test_bundle_spec(
  root : String,
  sign_binaries? : Array[String] = [],
) -> ProtonBundleSpec {
  let package_spec = @packager.PackageSpec::new(
    resolve_path(root, "app"),
    "Demo & App",
    "dev.proton.demo",
    "1.2.3",
    [@packager.PackageFormat::App],
    resolve_path(root, "dist"),
  )
  ProtonBundleSpec::new(
    package_spec,
    resolve_path(root, "cef_process"),
    resolve_path(root, "cef_requirements.json"),
    root,
    "1.2.3",
    "42",
    None,
    update_revision=42UL,
    sign_binaries~,
  )
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
  let spec = test_bundle_spec(".")
  let helper = macos_helper_specs(
      spec.package_spec.product_name,
      spec.package_spec.identifier,
    )[4]
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
  assert_true(plist.contains("<key>CFBundleVersion</key><string>42</string>"))
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
    BundlePlanError::NotLaunchableMachO(
      path="SeekMoon.app/Contents/MacOS/seekmoon",
      filetype=0xa,
    ).message(),
    content="bundle executable SeekMoon.app/Contents/MacOS/seekmoon is a Mach-O of type MH_DSYM, not MH_EXECUTE",
  )
}

///|
test "legacy Proton dynamic dependencies are recognized per platform" {
  assert_eq(
    legacy_dynamic_dependency(
      Macos,
      "/tmp/app:\n\t@rpath/libproton.dylib (compatibility version 0.0.0)",
    ),
    Some("libproton.dylib"),
  )
  assert_eq(
    legacy_dynamic_dependency(Linux, "libcef.so\nlibproton.so.1\nlibc.so.6"),
    Some("libproton.so"),
  )
  assert_eq(
    legacy_dynamic_dependency(
      Windows,
      "Image has the following dependencies:\r\n    PROTON.DLL\r\n",
    ),
    Some("proton.dll"),
  )
}

///|
test "current source-built dependencies do not match legacy libraries" {
  assert_eq(
    legacy_dynamic_dependency(Macos, "libcef.dylib\nlibc++.1.dylib"),
    None,
  )
  assert_eq(legacy_dynamic_dependency(Linux, "libcef.so\nlibc.so.6"), None)
  assert_eq(
    legacy_dynamic_dependency(Windows, "libcef.dll\nKERNEL32.dll"),
    None,
  )
}
