///|
test "package formats use stable command names" {
  assert_eq(PackageFormat::parse("app"), App)
  assert_eq(PackageFormat::parse("APPIMAGE"), AppImage)
  assert_eq(PackageFormat::Dmg.to_string(), "dmg")
}

///|
test "package formats use one host capability table" {
  assert_eq(resolve_package_formats_for_host([], Macos), [App, Zip])
  assert_eq(resolve_package_formats_for_host([], Windows), [App, Zip])
  assert_eq(resolve_package_formats_for_host([], Linux), [AppImage])
  try ignore(resolve_package_formats_for_host([App, App], Macos)) catch {
    DuplicateFormat(format~) => assert_eq(format, "app")
    _ => abort("expected a duplicate format error")
  } noraise {
    _ => abort("expected duplicate formats to be rejected")
  }
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
test "package metadata rejects path-unsafe values" {
  for product_name in ["Demo/App", "Demo\\App", "Demo:App", "Demo\nApp"] {
    try validate_product_name(product_name) catch {
      InvalidProductName(..) => ()
      _ => abort("expected an invalid product name")
    } noraise {
      _ => abort("expected an invalid product name")
    }
  }
  try validate_identifier("com.example.bad_value") catch {
    InvalidIdentifier(identifier="com.example.bad_value", ..) => ()
    _ => abort("expected an invalid identifier")
  } noraise {
    _ => abort("expected an invalid identifier")
  }
}

///|
test "package URL schemes are normalized before entering native metadata" {
  assert_eq(validate_url_schemes([" Demo+App "]), ["demo+app"])
  for schemes in [["1bad"], ["bad/scheme"], ["demo", "DEMO"]] {
    try ignore(validate_url_schemes(schemes)) catch {
      InvalidUrlScheme(..) => ()
      _ => abort("expected an invalid URL scheme")
    } noraise {
      _ => abort("expected an invalid URL scheme")
    }
  }
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
  let spec = PackageSpec(
    "/tmp/demo",
    "Demo & App",
    "dev.proton.demo",
    "1.2.3",
    [App],
    "/tmp/dist",
    url_schemes=["devtoys"],
    document_types=[DocumentType("Text", ["txt"], role="Editor")],
  )
  let plist = macos_info_plist(
    spec,
    PackageCustomization(macos_plist_strings=[
      MacosPlistString("Build&Revision", "42<"),
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
  let spec = PackageSpec(
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
fn package_test_spec(
  formats : Array[PackageFormat],
  url_schemes? : Array[String] = ["devtoys"],
) -> PackageSpec {
  PackageSpec(
    "/tmp/demo",
    "Demo App",
    "dev.proton.demo",
    "1.2.3",
    formats,
    "/tmp/dist",
    url_schemes~,
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
  let spec = package_test_spec([App, Nsis], url_schemes=["devtoys", "demo-app"])
  let script = windows_installer_script(spec, "C:\\stage\\Demo App")
  assert_true(script.contains("Name \"Demo App\""))
  assert_true(script.contains("VIProductVersion \"1.2.3.0\""))
  assert_true(script.contains("/PROTON-UPDATE="))
  assert_true(script.contains("taskkill /F /T /PID \"$ProtonUpdatePid\""))
  assert_true(
    script.contains("Rename \"$INSTDIR\" \"$INSTDIR.proton-previous\""),
  )
  assert_true(script.contains("Rename \"$INSTDIR.proton-next\" \"$INSTDIR\""))
  assert_true(script.contains("File /r \"C:\\stage\\Demo App\\*.*\""))
  assert_true(script.contains("Exec '\"$INSTDIR\\demo-app.exe\"'"))
  let empty_script = windows_installer_script(
    package_test_spec([App, Nsis], url_schemes=[]),
    "C:\\stage\\Demo App",
  )
  assert_true(
    empty_script.contains(
      "DeleteRegKey HKLM \"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\dev.proton.demo\"\nSectionEnd",
    ),
  )
  assert_true(
    script.contains(
      "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\dev.proton.demo",
    ),
  )
  assert_true(windows_installer_path(spec).has_suffix("demo-app-setup.exe"))
}

///|
test "NSIS staging transaction leaves the working directory before moving or removing it" {
  let script = windows_installer_script(
    package_test_spec([App, Nsis]),
    "C:\\stage\\Demo App",
  )
  let (_, install) = script.split_once("Section \"Install\"\n").unwrap()
  let (transaction, _) = install
    .to_owned()
    .split_once("  WriteRegStr HKLM")
    .unwrap()
  inspect(
    transaction.to_owned(),
    content=(
      #|  ; Expand the complete release beside the installed tree before moving
      #|  ; either one. A failed extraction therefore leaves the old app intact.
      #|  RMDir /r "$INSTDIR.proton-next"
      #|  SetOutPath "$INSTDIR.proton-next"
      #|  ClearErrors
      #|  File /r "C:\stage\Demo App\*.*"
      #|  IfErrors install_failed
      #|  ClearErrors
      #|  WriteUninstaller "$INSTDIR.proton-next\Uninstall.exe"
      #|  IfErrors install_failed
      #|  ; SetOutPath also changes the working directory, which Windows locks.
      #|  SetOutPath "$TEMP"
      #|
      #|  ; Reaching a later update proves the current tree started successfully,
      #|  ; so its predecessor is no longer needed as the recovery copy.
      #|  RMDir /r "$INSTDIR.proton-previous"
      #|  IfFileExists "$INSTDIR\*.*" 0 promote_update
      #|  ; The updater names the exact process tree it is replacing. A manual
      #|  ; reinstall has no such token and falls back to the executable name.
      #|  ${If} $ProtonUpdate == "1"
      #|    nsExec::Exec 'taskkill /F /T /PID "$ProtonUpdatePid"'
      #|  ${Else}
      #|    nsExec::Exec 'taskkill /F /T /IM "demo-app.exe"'
      #|  ${EndIf}
      #|  Pop $0
      #|  Sleep 500
      #|  ClearErrors
      #|  Rename "$INSTDIR" "$INSTDIR.proton-previous"
      #|  IfErrors install_failed
      #|promote_update:
      #|  ClearErrors
      #|  Rename "$INSTDIR.proton-next" "$INSTDIR"
      #|  IfErrors 0 install_complete
      #|  Rename "$INSTDIR.proton-previous" "$INSTDIR"
      #|  Abort "The new installation could not be moved into place."
      #|install_failed:
      #|  SetOutPath "$TEMP"
      #|  RMDir /r "$INSTDIR.proton-next"
      #|  Abort "The update could not be installed."
      #|install_complete:
      #|  SetOutPath "$INSTDIR"
      #|
      #|
    ),
  )
}

///|
test "NSIS URL scheme scripts share an owned command" {
  let spec = package_test_spec([App, Nsis], url_schemes=["devtoys"])
  inspect(
    windows_protocol_install_script(spec, "demo-app.exe"),
    content=(
      #|  WriteRegStr HKCU "Software\Classes\devtoys" "" "URL:devtoys"
      #|  WriteRegStr HKCU "Software\Classes\devtoys" "URL Protocol" ""
      #|  WriteRegStr HKCU "Software\Classes\devtoys\shell\open\command" "" "$\"$INSTDIR\demo-app.exe$\" $\"%1$\""
      #|
    ),
  )
  inspect(
    windows_protocol_uninstall_script(spec, "demo-app.exe"),
    content=(
      #|  ReadRegStr $0 HKCU "Software\Classes\devtoys\shell\open\command" ""
      #|  ${If} $0 == "$\"$INSTDIR\demo-app.exe$\" $\"%1$\""
      #|    DeleteRegKey HKCU "Software\Classes\devtoys"
      #|  ${EndIf}
      #|
    ),
  )
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
      $|Exec=demo-app %U
      $|Icon=demo-app
      $|X-AppImage-Version=1.2.3
      $|MimeType=x-scheme-handler/devtoys;
      $|
    ),
  )
  assert_eq(linux_desktop_name(spec), "dev.proton.demo.desktop")
  let apprun = linux_apprun("demo-app", linux_desktop_name(spec))
  assert_true(apprun.contains("HERE=\"$APPDIR\""))
  assert_true(apprun.contains("CHROME_DESKTOP=\"dev.proton.demo.desktop\""))
  inspect(
    apprun,
    content=(
      $|#!/bin/sh
      $|HERE="$APPDIR"
      $|export CHROME_DESKTOP="dev.proton.demo.desktop"
      $|exec "$HERE/usr/bin/demo-app" "$@"
      $|
    ),
  )
}
