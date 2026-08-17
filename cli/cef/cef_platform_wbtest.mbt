///|
test "darwin arm64 platform has complete CEF and Proton runtime artifact lists" {
  let platform = darwin_arm64_platform()
  let prebuilt = proton_prebuilt_relative_files(platform)
  assert_true(prebuilt.contains("bin/cef_process"))
  assert_true(prebuilt.contains("lib/libproton.dylib"))
  assert_true(prebuilt.contains("include/proton_native.h"))
  let cef = installed_cef_relative_files(platform)
  // The artifact list uses the current host's separator even when this test
  // inspects the macOS platform description from Windows.
  let sandbox_library = @fsutil.path_join(
    "Release/Chromium Embedded Framework.framework/Libraries", "libcef_sandbox.dylib",
  )
  assert_true(cef.contains(sandbox_library))
  let runtime = runtime_required_relative_files(platform)
  assert_true(runtime.contains("bin/cef_process"))
  assert_true(runtime.contains("lib/libproton.dylib"))
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
  assert_true(macos.contains("lib/libproton.dylib"))
  assert_false(macos.contains("bin\\proton.dll"))
  let windows = runtime_required_relative_files_for_platform("win32-x64")
  assert_true(windows.contains("bin\\proton.dll"))
  assert_true(
    runtime_required_relative_files_for_platform("unknown").length() == 0,
  )
}

///|
test "runtime cache paths are absolute and user-level by default" {
  let project_root = @fsutil.resolve_path(".", "fixtures/proton-cache-project")
  let home = @fsutil.resolve_path(project_root, "../proton-cache-home")
  assert_eq(
    resolve_global_runtime_cache_root(
      project_root~,
      configured_root=None,
      home=Some(home),
    ),
    Some(@fsutil.resolve_path(home, ".proton/runtimes")),
  )
  assert_eq(
    resolve_global_runtime_cache_root(
      project_root~,
      configured_root=Some("../shared-runtimes"),
      home=Some("ignored-home"),
    ),
    Some(@fsutil.resolve_path(project_root, "../shared-runtimes")),
  )
}

///|
test "runtime cache identity includes Proton and CEF content" {
  let proton_a = "sha256:" + "a".repeat(64)
  let proton_b = "sha256:" + "b".repeat(64)
  let cef_a = "c".repeat(64)
  let cef_b = "d".repeat(64)
  let base = proton_runtime_id("0.1.16", proton_a, cef_a)
  assert_eq(base, proton_runtime_id("0.1.16", proton_a, cef_a))
  assert_true(base.has_prefix("proton-0.1.16-"))
  assert_false(base == proton_runtime_id("0.1.16", proton_b, cef_a))
  assert_false(base == proton_runtime_id("0.1.16", proton_a, cef_b))
}

///|
test "CEF cache paths are absolute and scoped by platform and archive" {
  let project_root = @fsutil.resolve_path(".", "fixtures/proton-cache-project")
  let home = @fsutil.resolve_path(project_root, "../proton-cache-home")
  let cache_root = resolve_global_cef_cache_root(
    project_root~,
    configured_root=None,
    home=Some(home),
  ).unwrap()
  let platform = darwin_arm64_platform()
  let actual = cef_cache_dir(cache_root~, platform~, name="cef-test")
  let expected = @fsutil.path_join(
    @fsutil.path_join(
      @fsutil.resolve_path(home, ".proton/cache/cef"),
      "darwin-arm64",
    ),
    "cef-test",
  )
  assert_true(@fsutil.path_is_absolute(actual))
  assert_eq(actual, expected)
}

///|
test "relative CEF cache overrides resolve from the project root" {
  let project_root = @fsutil.resolve_path(".", "fixtures/proton-cache-project")
  let actual = resolve_global_cef_cache_root(
    project_root~,
    configured_root=Some("../shared-cef"),
    home=Some("ignored-home"),
  )
  assert_eq(actual, Some(@fsutil.resolve_path(project_root, "../shared-cef")))
  assert_eq(
    resolve_global_cef_cache_root(
      project_root~,
      configured_root=None,
      home=None,
    ),
    None,
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
    try validate_cef_name(name) catch {
      CefUsageError::InvalidArchiveName(name=actual) => assert_eq(actual, name)
      _ => abort("expected invalid CEF archive name")
    } noraise {
      _ => abort("expected unsafe CEF name to fail: " + name)
    }
  }
  validate_cef_name(
    "cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_macosarm64_minimal",
  )
}

///|
test "default CEF archives have pinned SHA-256 digests" {
  for
    platform in [
      win32_x64_platform(),
      darwin_arm64_platform(),
      linux_x64_platform(),
    ] {
    let value = resolve_cef_archive_sha256(
      platform,
      platform.default_cef_name,
      None,
      None,
    )
    assert_true(valid_sha256(value))
  }
}

///|
test "custom CEF archives require a valid SHA-256 digest" {
  let platform = darwin_arm64_platform()
  try
    resolve_cef_archive_sha256(
      platform,
      "custom",
      Some("https://example.test/cef"),
      None,
    )
  catch {
    CefUsageError::MissingCustomChecksum => ()
    _ => abort("expected missing custom checksum")
  } noraise {
    _ => abort("expected missing custom checksum to fail")
  }
  try
    resolve_cef_archive_sha256(platform, "custom", None, Some("invalid"))
  catch {
    CefUsageError::InvalidChecksum(value="invalid") => ()
    _ => abort("expected invalid custom checksum")
  } noraise {
    _ => abort("expected invalid custom checksum to fail")
  }
  let uppercase = "C105F69C0D4DC14331BE12CEE967EEB73FA4897A6ECDE244051318491CD381C7"
  let value = resolve_cef_archive_sha256(
    platform,
    "custom",
    None,
    Some(uppercase),
  )
  assert_eq(value, uppercase.to_lower())
}

///|
test "manifest proton versions cannot escape generated directories" {
  for
    version in [
      "../evil", "a/../../b", "a\\..\\b", "/tmp/evil", "C:\\evil", ".", "..", "",
      "with space", "0.1.12\n",
    ] {
    try validate_proton_version(version, "manifest.json") catch {
      CefRuntimeError::ManifestFieldValue(field="proton_version", ..) => ()
      _ => abort("expected invalid proton version: " + version)
    } noraise {
      _ => abort("expected unsafe proton version to fail: " + version)
    }
  }
  for version in ["0.1.12", "0.1.13-beta.1+build", "1.0.0_rc1"] {
    validate_proton_version(version, "manifest.json")
  }
}

///|
test "generated runtime directories must stay under the cache root" {
  let root = "/Users/test/.proton/runtimes"
  assert_safe_generated_dir(
    "/Users/test/.proton/runtimes/darwin-arm64/proton-0.1.12-x", root,
  )
  for
    dir in [
      root,
      "/Users/test/.proton",
      "/.proton/runtimes/darwin-arm64/x",
      "/Users/test/.proton/runtimes.evil/x",
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
  let root = @fsutil.resolve_path(".", "fixtures/proton-cef-project")
  let cache = @fsutil.resolve_path(".", "fixtures/proton-cef-cache/runtime")
  assert_safe_install_dir(cache, root)
  let parent = @fsutil.path_parent(root)
  let mut filesystem_root = root
  for ;; {
    let next = @fsutil.path_parent(filesystem_root)
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
