///|
fn runtime_required_relative_files_for_platform(
  platform_id : String,
) -> Array[String] {
  match platform_from_override(Some(platform_id)) {
    Some(platform) => runtime_required_relative_files(platform)
    None => []
  }
}

///|
test "darwin arm64 platform has complete CEF runtime artifact lists" {
  let platform = darwin_arm64_platform()
  let cef = installed_cef_relative_files(platform)
  // The artifact list uses the current host's separator even when this test
  // inspects the macOS platform description from Windows.
  let sandbox_library = path_join(
    "Release/Chromium Embedded Framework.framework/Libraries", "libcef_sandbox.dylib",
  )
  assert_true(cef.contains(sandbox_library))
  let runtime = runtime_required_relative_files(platform)
  assert_false(runtime.contains("bin/cef_process"))
  assert_false(runtime.contains("lib/libproton.dylib"))
  assert_true(
    runtime.contains(
      "Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework",
    ),
  )
  assert_true(
    runtime.contains(
      "Frameworks/Chromium Embedded Framework.framework/Libraries/libcef_sandbox.dylib",
    ),
  )
  assert_true(runtime.contains("Resources/icudtl.dat"))
}

///|
test "public runtime layout lookup follows stable platform ids" {
  let macos = runtime_required_relative_files_for_platform("darwin-arm64")
  assert_true(
    macos.contains(
      "Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework",
    ),
  )
  let windows = runtime_required_relative_files_for_platform("win32-x64")
  assert_true(windows.contains("bin\\libcef.dll"))
  assert_true(
    runtime_required_relative_files_for_platform("unknown").length() == 0,
  )
}

///|
test "runtime cache identity is the CEF content digest" {
  let cef_a = "c".repeat(64)
  let cef_b = "d".repeat(64)
  assert_eq(
    cef_runtime_id(cef_a),
    "cef-" + cef_a + "-layout-" + runtime_layout_version.to_string(),
  )
  assert_false(cef_runtime_id(cef_a) == cef_runtime_id(cef_b))
}

///|
test "runtime installation contains no machine paths in its manifest" {
  let requirement = runtime_requirement(darwin_arm64_platform())
  let manifest = runtime_manifest_json(requirement)
  assert_true(manifest.contains("\"sdk\":\"sdk\""))
  assert_true(manifest.contains("\"runtime\":\"runtime\""))
  assert_false(manifest.contains("/Users/"))
  assert_false(manifest.contains("C:\\"))
}

///|
test "host platform detection keeps macOS CPU architecture" {
  let arm64 = platform_from_host(windows=false, macos=true, arch=Some("arm64"))
  assert_eq(arm64.id, "darwin-arm64")
  assert_true(arm64.supported)
  let x64 = platform_from_host(windows=false, macos=true, arch=Some("x86_64"))
  assert_eq(x64.id, "darwin-x64")
  assert_false(x64.supported)
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
test "default CEF archives have pinned SHA-256 digests" {
  for
    platform in [
      win32_x64_platform(),
      darwin_arm64_platform(),
      linux_x64_platform(),
    ] {
    let value = platform.default_cef_sha256
    assert_eq(value.length(), 64)
    for ch in value {
      assert_true(ch.is_ascii_digit() || (ch >= 'a' && ch <= 'f'))
    }
  }
}

///|
test "generated runtime directories must stay under the store root" {
  let root = "/Users/test/.proton/store"
  assert_safe_generated_dir(
    "/Users/test/.proton/store/darwin-arm64/cef-content-hash", root,
  )
  for
    dir in [
      root,
      "/Users/test/.proton",
      "/.proton/store/darwin-arm64/x",
      "/Users/test/.proton/store.evil/x",
      "",
      root + "/",
    ] {
    try assert_safe_generated_dir(dir, root) catch {
      CefRuntimeError::UnsafeGeneratedDirectory(..) => ()
      _ => abort("expected unsafe generated directory: " + dir)
    } noraise {
      _ => abort("expected unsafe generated directory to fail: " + dir)
    }
  }
}

///|
test "CEF installation never removes a project boundary or filesystem root" {
  let root = resolve_path(".", "fixtures/proton-cef-project")
  let cache = resolve_path(".", "fixtures/proton-cef-cache/runtime")
  assert_safe_install_dir(cache, root)
  let parent = path_parent(root)
  let mut filesystem_root = root
  for ;; {
    let next = path_parent(filesystem_root)
    if next == filesystem_root {
      break
    }
    filesystem_root = next
  }
  for dir in ["", root, parent, filesystem_root] {
    try assert_safe_install_dir(dir, root) catch {
      CefRuntimeError::UnsafeInstallDirectory(..) => ()
      _ => abort("expected unsafe install directory: " + dir)
    } noraise {
      _ => abort("expected unsafe install directory to fail: " + dir)
    }
  }
}
