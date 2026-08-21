///|
test "package formats use stable command names" {
  assert_eq(PackageFormat::parse("app"), App)
  assert_eq(PackageFormat::parse("APPIMAGE"), AppImage)
  assert_eq(PackageFormat::Dmg.to_string(), "dmg")
}

///|
test "package identifiers require reverse-DNS form" {
  assert_eq(validate_identifier("com.example.app"), "com.example.app")
  let mut rejected = false
  try validate_identifier("app") catch {
    InvalidIdentifier(..) => rejected = true
    _ => ()
  } noraise {
    _ => ()
  }
  assert_true(rejected)
}

///|
test "package versions cannot escape package paths" {
  for version in ["1.2", "v1", "2026.08", "1.2.3-beta.1+build.5"] {
    assert_eq(validate_package_version(version), version)
  }
  for
    version in [
      "", "1.2.3/../../outside", "1.2.3\\outside", "1.2.3\nExec=outside",
    ] {
    let mut rejected = false
    try validate_package_version(version) catch {
      InvalidVersion(..) => rejected = true
      _ => ()
    } noraise {
      _ => ()
    }
    assert_true(rejected)
  }
}

///|
test "payload destinations cannot escape their package area" {
  validate_relative_destination("assets/icon.png")
  let mut rejected = false
  try validate_relative_destination("../secret") catch {
    InvalidPayload(..) => rejected = true
    _ => ()
  } noraise {
    _ => ()
  }
  assert_true(rejected)
}

///|
test "executable names are stable and filesystem safe" {
  assert_eq(executable_name("My Proton App!"), "my-proton-app")
  assert_eq(executable_name("  ---  "), "app")
}

///|
test "macOS plist customization is escaped" {
  let spec = PackageSpec::new(
    "/tmp/demo",
    "Demo & App",
    "dev.proton.demo",
    "1.2.3",
    [App],
    "/tmp/dist",
    url_schemes=["devtoys"],
    document_types=[DocumentType::new("Text", ["txt"], role="Editor")],
  )
  let plist = macos_info_plist(
    spec,
    PackageCustomization::new(macos_plist_strings=[
      MacosPlistString::new("Build&Revision", "42<"),
    ]),
    "demo-app",
    "1.2.3",
    "42",
  )
  assert_true(plist.contains("<string>Demo &amp; App</string>"))
  assert_true(
    plist.contains("<key>Build&amp;Revision</key><string>42&lt;</string>"),
  )
  assert_true(plist.contains("CFBundleURLTypes"))
  assert_true(plist.contains("CFBundleDocumentTypes"))
}

///|
#cfg(target="wasm")
test "Windows icon embedding reports the native-only operation" {
  let spec = PackageSpec::new(
    "demo.exe",
    "Demo",
    "dev.proton.demo",
    "1.0.0",
    [App],
    "dist",
    icons=["demo.ico"],
  )
  try stage_windows_icon(spec, "staging/demo.exe") catch {
    WindowsPackagingError::ToolFailure(stage~, detail~) => {
      assert_eq(stage, "embed Windows application icon")
      assert_true(detail.contains("native proton_package backend"))
    }
    _ => abort("expected a Windows icon backend error")
  } noraise {
    _ => abort("expected Windows icon embedding to fail on wasm")
  }
}

///|
fn package_test_spec(formats : Array[PackageFormat]) -> PackageSpec {
  PackageSpec::new(
    "/tmp/demo", "Demo App", "dev.proton.demo", "1.2.3", formats, "/tmp/dist",
  )
}

///|
test "macOS signing uses hardened runtime and stable identifiers" {
  let args = macos_codesign_args(
    "Developer ID Application: Example",
    "cef_process",
    runtime_options=true,
    entitlements=Some("proton.entitlements"),
    identifier=Some("cef_process"),
  )
  assert_true(args.contains("--timestamp"))
  assert_true(args.contains("--options"))
  assert_true(args.contains("runtime"))
  assert_true(args.contains("--entitlements"))
  assert_true(args.contains("-i"))
  assert_eq(args[args.length() - 1], "cef_process")
  @debug.assert_eq(macos_codesign_verify_args("Demo.app", deep=true), [
    "--verify", "--deep", "--strict", "--verbose=2", "Demo.app",
  ])
}

///|
test "default macOS entitlements distinguish ad-hoc signing" {
  let release = default_macos_entitlements(allow_untrusted_libraries=false)
  assert_true(release.contains("com.apple.security.cs.allow-jit"))
  assert_false(release.contains("disable-library-validation"))
  let adhoc = default_macos_entitlements(allow_untrusted_libraries=true)
  assert_true(adhoc.contains("disable-library-validation"))
}

///|
test "NSIS versions and quoting follow installer syntax" {
  assert_eq(windows_installer_version_quad("1.0.0"), "1.0.0.0")
  assert_eq(windows_installer_version_quad("1.2.3-beta.4"), "1.2.3.0")
  assert_eq(
    windows_installer_quote("C:\\Program Files\\Demo"),
    "C:\\Program Files\\Demo",
  )
  assert_eq(windows_installer_quote("Cost $5"), "Cost $$5")
  assert_eq(windows_installer_quote("say \"hi\""), "say $\\\"hi$\\\"")
}

///|
test "NSIS script carries package identity and update behavior" {
  let spec = package_test_spec([App, Nsis])
  let script = windows_installer_script(spec, "C:\\stage\\Demo App")
  assert_true(script.contains("Name \"Demo App\""))
  assert_true(script.contains("VIProductVersion \"1.2.3.0\""))
  assert_true(script.contains("taskkill /F /IM \"demo-app.exe\""))
  assert_true(script.contains("File /r \"C:\\stage\\Demo App\\*.*\""))
  assert_true(
    script.contains(
      "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\dev.proton.demo",
    ),
  )
  assert_true(windows_installer_path(spec).has_suffix("demo-app-setup.exe"))
}

///|
test "AppImage metadata points at the staged executable" {
  let spec = package_test_spec([AppImage])
  let entry = linux_desktop_entry(spec, "demo-app")
  inspect(
    entry,
    content=(
      $|[Desktop Entry]
      $|Type=Application
      $|Terminal=false
      $|Categories=Utility;
      $|Name=Demo App
      $|Exec=demo-app
      $|Icon=demo-app
      $|X-AppImage-Version=1.2.3
      $|
    ),
  )
  let apprun = linux_apprun("demo-app")
  assert_true(apprun.contains("HERE=\"$APPDIR\""))
  inspect(
    apprun,
    content=(
      $|#!/bin/sh
      $|HERE="$APPDIR"
      $|exec "$HERE/usr/bin/demo-app" "$@"
      $|
    ),
  )
}
