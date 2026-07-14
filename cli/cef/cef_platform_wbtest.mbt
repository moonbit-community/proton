///|
test "darwin arm64 platform has proton and runtime artifact lists" {
  let platform = darwin_arm64_platform()
  let prebuilt = proton_prebuilt_relative_files(platform)
  assert_true(prebuilt.contains("bin/cef_process"))
  assert_true(prebuilt.contains("lib/libproton.dylib"))
  assert_true(prebuilt.contains("include/proton_native.h"))
  let runtime = runtime_required_relative_files(platform)
  assert_true(runtime.contains("bin/cef_process"))
  assert_true(runtime.contains("lib/libproton.dylib"))
  assert_true(
    runtime.contains(
      "Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework",
    ),
  )
  assert_true(runtime.contains("Resources/icudtl.dat"))
}

///|
test "public runtime layout lookup follows stable platform ids" {
  let macos = runtime_required_relative_files_for_platform("darwin-arm64")
  assert_true(macos.contains("lib/libproton.dylib"))
  assert_false(macos.contains("bin\\proton.dll"))
  let windows = runtime_required_relative_files_for_platform("win32-x64")
  assert_true(windows.contains("bin\\proton.dll"))
  assert_true(
    runtime_required_relative_files_for_platform("unknown").length() == 0,
  )
}

///|
test "host platform detection keeps macOS CPU architecture" {
  let arm64 = platform_from_host(windows=false, macos=true, arch=Some("arm64"))
  assert_eq(arm64.id, "darwin-arm64")
  assert_true(arm64.supported)
  let x64 = platform_from_host(windows=false, macos=true, arch=Some("x86_64"))
  assert_eq(x64.id, "darwin-x64")
  assert_false(x64.supported)
  assert_eq(x64.cef_suffix, "_macosx64_minimal")
}

///|
test "host platform detection does not guess arm64 for unknown macOS arch" {
  let unknown = platform_from_host(
    windows=false,
    macos=true,
    arch=Some("powerpc"),
  )
  assert_eq(unknown.id, "darwin-powerpc")
  assert_false(unknown.supported)
}

///|
test "platform override accepts stable platform ids" {
  match platform_from_override(Some("darwin-x64")) {
    Some(platform) => {
      assert_eq(platform.id, "darwin-x64")
      assert_false(platform.supported)
    }
    None => abort("expected darwin-x64 override")
  }
  match platform_from_override(Some("linux-x64")) {
    Some(platform) => {
      assert_eq(platform.id, "linux-x64")
      assert_true(platform.supported)
    }
    None => abort("expected linux-x64 override")
  }
}

///|
test "CEF archive names cannot escape generated directories" {
  for
    name in [
      "../cef", "cef/../../outside", "cef\\..\\outside", "/tmp/cef", "C:\\cef", ".",
      "..", "",
    ] {
    match validate_cef_name(name) {
      Ok(_) => abort("expected unsafe CEF name to fail: " + name)
      Err(_) => ()
    }
  }
  match
    validate_cef_name(
      "cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_macosarm64_minimal",
    ) {
    Ok(_) => ()
    Err(_) => abort("expected default CEF name to pass")
  }
}
