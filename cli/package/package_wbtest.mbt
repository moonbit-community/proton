///|
fn parse_package_args(args : Array[String]) -> RawPackageOptions raise {
  package_options_from_matches(command().parse(argv=args, env=Map([])))
}

///|
test "parse package args accepts repeated targets and overrides" {
  let raw = parse_package_args([
    "--package", "desktop", "--target", "app", "--target", "zip", "--output", "dist",
    "--no-build", "--dry-run",
  ])
  assert_eq(raw.app_package, "desktop")
  @debug.assert_eq(raw.targets, ["app", "zip"])
  @debug.assert_eq(raw.output, Some("dist"))
  assert_false(raw.build)
  assert_true(raw.dry_run)
}

///|
test "parse package args rejects unsupported target" {
  try parse_package_args(["--target", "dmg"]) catch {
    PackageUsageError::UnsupportedTarget(target="dmg") => ()
    _ => abort("expected unsupported target")
  } noraise {
    _ => abort("expected unsupported target")
  }
}

///|
test "notarize implies signing" {
  let raw = parse_package_args(["--notarize", "--dry-run"])
  assert_true(raw.sign)
  assert_true(raw.notarize)
  assert_true(raw.dry_run)
}

///|
test "sign does not require notarization" {
  let raw = parse_package_args(["--sign"])
  assert_true(raw.sign)
  assert_false(raw.notarize)
}

///|
test "package plan requires active bundle" {
  let project = @proton_config.ProjectConfig::new(
    ".",
    @proton_config.ProjectWindowConfig::new("Demo", 800, 600),
    @proton_config.ProjectEntry::Html("<main>demo</main>"),
    @proton_config.ProjectMetadata::new(
      "Demo",
      identifier=Some("dev.proton.demo"),
      version=Some("1.0.0"),
    ),
  )
  let raw = parse_package_args([])
  try build_package_plan(raw, "moon.proton", project) catch {
    PackageConfigError::BundleMissing => ()
    _ => abort("expected missing bundle error")
  } noraise {
    _ => abort("expected missing bundle error")
  }
}

///|
test "package plan defaults to app and zip" {
  let project = @proton_config.ProjectConfig::new(
    ".",
    @proton_config.ProjectWindowConfig::new("Demo", 800, 600),
    @proton_config.ProjectEntry::Html("<main>demo</main>"),
    @proton_config.ProjectMetadata::new(
      "Demo",
      identifier=Some("dev.proton.demo"),
      version=Some("1.0.0"),
    ),
    bundle=Some(@proton_config.ProjectBundleConfig::new(active=true)),
  )
  let raw = parse_package_args([])
  let plan = build_package_plan(raw, "moon.proton", project)
  @debug.assert_eq(plan.targets, ["app", "zip"])
  assert_eq(plan.identifier, "dev.proton.demo")
  assert_eq(plan.version, "1.0.0")
  assert_true(
    normalize_slashes(plan.build_target_dir).has_suffix(
      "/target/proton-package-build/dev-proton-demo",
    ),
  )
}

///|
#cfg(not(platform="windows"))
test "macOS package paths normalize absolute and relative inputs" {
  let base = resolve_path("target", "proton package path base")
  assert_eq(resolve_path(base, "/"), "/")
  assert_eq(
    resolve_path(base, "/tmp/proton absolute path"),
    "/tmp/proton absolute path",
  )
  assert_eq(
    resolve_path(base, "relative/file.txt"),
    base + "/relative/file.txt",
  )
  assert_eq(
    resolve_path(base, ".proton/runtime.json"),
    base + "/.proton/runtime.json",
  )
  assert_eq(
    resolve_path(base, "directory with spaces/file.txt"),
    base + "/directory with spaces/file.txt",
  )
  assert_eq(
    resolve_path(base, "../sibling"),
    resolve_path(path_parent(base), "sibling"),
  )
  assert_eq(resolve_path(base, "nested\\child.txt"), base + "/nested/child.txt")
  assert_eq(resolve_path(base, "\\tmp\\proton path"), "/tmp/proton path")
}

///|
#cfg(not(platform="windows"))
async test "macOS ensure_dir recursively creates absolute paths with spaces" {
  let root = resolve_path("target", "proton package ensure dir")
  remove_tree(root)
  let nested = resolve_path(root, "parent with spaces/child/grandchild")
  ensure_dir(nested)
  assert_true(path_is_dir(nested))
}

///|
test "package executable name is filesystem safe" {
  assert_eq(package_executable_name("My Proton App!"), "my-proton-app")
  assert_eq(package_executable_name("  ---  "), "proton-app")
}

///|
test "macOS package metadata validation rejects unsafe values" {
  try validate_product_name("Demo/App") catch {
    PackagePlanError::InvalidProductName(reason~) =>
      assert_true(reason.contains("path-unsafe character"))
    _ => abort("expected unsafe product name")
  } noraise {
    _ => abort("expected unsafe product name")
  }
  try validate_product_name("Demo\nApp") catch {
    PackagePlanError::InvalidProductName(reason~) =>
      assert_true(reason.contains("ASCII control character"))
    _ => abort("expected control character error")
  } noraise {
    _ => abort("expected control character error")
  }
  try validate_bundle_identifier("demo") catch {
    PackagePlanError::InvalidIdentifier(identifier="demo", reason~) =>
      assert_true(reason.contains("reverse-DNS"))
    _ => abort("expected reverse-DNS identifier error")
  } noraise {
    _ => abort("expected reverse-DNS identifier error")
  }
  try validate_bundle_identifier("com.example.bad_value") catch {
    PackagePlanError::InvalidIdentifier(
      identifier="com.example.bad_value",
      reason~
    ) => assert_true(reason.contains("unsupported character"))
    _ => abort("expected identifier character error")
  } noraise {
    _ => abort("expected identifier character error")
  }
}

///|
test "macOS version normalizes semantic prerelease to plist versions" {
  let old_build = @sys.get_env_var("PROTON_MACOS_BUILD_NUMBER")
  @sys.unset_env_var("PROTON_MACOS_BUILD_NUMBER")
  defer restore_package_env("PROTON_MACOS_BUILD_NUMBER", old_build)
  let (short_version, bundle_version) = validate_macos_version("1.2.3-beta.1")
  assert_eq(short_version, "1.2.3")
  assert_eq(bundle_version, "1.2.3")
  let (short_version, bundle_version) = validate_macos_version(
    "1.2.3+release.4",
  )
  assert_eq(short_version, "1.2.3")
  assert_eq(bundle_version, "1.2.3")
  @sys.set_env_var("PROTON_MACOS_BUILD_NUMBER", "42.7")
  let (short_version, bundle_version) = validate_macos_version("1.2.3")
  assert_eq(short_version, "1.2.3")
  assert_eq(bundle_version, "42.7")
  @sys.set_env_var("PROTON_MACOS_BUILD_NUMBER", "42.beta")
  try validate_macos_version("1.2.3") catch {
    PackagePlanError::InvalidVersion(reason~, ..) =>
      assert_true(reason.contains("PROTON_MACOS_BUILD_NUMBER"))
    _ => abort("expected invalid build number")
  } noraise {
    _ => abort("expected invalid build number error")
  }
  @sys.unset_env_var("PROTON_MACOS_BUILD_NUMBER")
  try validate_macos_version("1.two.3") catch {
    PackagePlanError::InvalidVersion(reason~, ..) =>
      assert_true(reason.contains("must be numeric"))
    _ => abort("expected numeric version error")
  } noraise {
    _ => abort("expected numeric version error")
  }
}

///|
test "default macOS entitlements enable CEF JIT without disabling validation" {
  let entitlements = default_macos_entitlements(allow_untrusted_libraries=false)
  assert_true(entitlements.contains("com.apple.security.cs.allow-jit"))
  assert_true(
    entitlements.contains(
      "com.apple.security.cs.allow-unsigned-executable-memory",
    ),
  )
  assert_false(entitlements.contains("disable-library-validation"))
  let adhoc_entitlements = default_macos_entitlements(
    allow_untrusted_libraries=true,
  )
  assert_true(adhoc_entitlements.contains("disable-library-validation"))
}

///|
test "macOS signing args apply hardened runtime entitlements to app code" {
  let args = macos_codesign_args(
    "Developer ID Application: Example",
    "Demo.app",
    runtime_options=true,
    deep=false,
    entitlements=Some("proton.entitlements"),
  )
  assert_true(args.contains("--timestamp"))
  assert_true(args.contains("--options"))
  assert_true(args.contains("runtime"))
  assert_true(args.contains("--entitlements"))
  assert_true(args.contains("proton.entitlements"))
  assert_false(args.contains("--deep"))
  assert_eq(args[args.length() - 1], "Demo.app")
}

///|
test "ad-hoc macOS signing requires an explicit diagnostic opt-in" {
  let old = @sys.get_env_var("PROTON_MACOS_ALLOW_ADHOC")
  defer restore_package_env("PROTON_MACOS_ALLOW_ADHOC", old)
  @sys.unset_env_var("PROTON_MACOS_ALLOW_ADHOC")
  assert_false(macos_adhoc_signing_allowed())
  try validate_macos_signing_identity("-", notarize=false) catch {
    MacosSigningError::InvalidConfiguration(_) => ()
    _ => abort("expected ad-hoc signing rejection")
  } noraise {
    _ => abort("expected ad-hoc signing rejection")
  }
  @sys.set_env_var("PROTON_MACOS_ALLOW_ADHOC", "yes")
  assert_true(macos_adhoc_signing_allowed())
  assert_true(validate_macos_signing_identity("-", notarize=false))
  assert_false(
    validate_macos_signing_identity("Apple Development: Example", notarize=true),
  )
  try validate_macos_signing_identity("-", notarize=true) catch {
    MacosSigningError::InvalidConfiguration(detail~) =>
      assert_true(detail.contains("Developer ID Application"))
    _ => abort("expected ad-hoc notarization rejection")
  } noraise {
    _ => abort("expected ad-hoc notarization rejection")
  }
  @sys.set_env_var("PROTON_MACOS_ALLOW_ADHOC", "false")
  assert_false(macos_adhoc_signing_allowed())
}

///|
test "macOS framework signing uses deep sealing without app entitlements" {
  let args = macos_codesign_args(
    "Developer ID Application: Example",
    "Chromium Embedded Framework.framework",
    runtime_options=false,
    deep=true,
    entitlements=Some("proton.entitlements"),
  )
  assert_true(args.contains("--deep"))
  assert_false(args.contains("--options"))
  assert_false(args.contains("--entitlements"))
}

///|
async test "macOS signing rejects a missing required target" {
  let missing = resolve_path("target", "proton-package-missing-signing-target")
  remove_tree(missing)
  try
    require_macos_codesign_targets([
      MacosCodeSignTarget::{
        path: missing,
        runtime_options: false,
        deep: false,
      },
    ])
  catch {
    MacosSigningError::MissingTarget(path~) => assert_eq(path, missing)
    _ => abort("expected missing signing target")
  } noraise {
    _ => abort("expected missing signing target failure")
  }
}

///|
test "macOS signature verification args seal nested bundles deeply" {
  let app_args = macos_codesign_verify_args("Demo.app", deep=true)
  @debug.assert_eq(app_args, [
    "--verify", "--deep", "--strict", "--verbose=2", "Demo.app",
  ])
  let dylib_args = macos_codesign_verify_args("libproton.dylib", deep=false)
  @debug.assert_eq(dylib_args, [
    "--verify", "--strict", "--verbose=2", "libproton.dylib",
  ])
}

///|
test "macOS icon plist entry is conditional" {
  assert_eq(macos_icon_plist_entry(None), "")
  assert_true(macos_icon_plist_entry(Some("icon.icns")).contains("AppIcon"))
}

///|
async test "macOS icon selection stages icns and rejects a missing source" {
  let root = resolve_path("target", "proton-package-macos-icon")
  remove_tree(root)
  let resources = resolve_path(root, "Resources")
  let icon = resolve_path(root, "Demo.ICNS")
  ensure_dir(resources)
  write_text(icon, "test-icns")
  match first_macos_icon(["icon.png", icon]) {
    Some(selected) => assert_eq(selected, icon)
    None => abort("expected .icns icon selection")
  }
  let plan = PackagePlan::{
    root,
    workspace_root: root,
    build_target_dir: resolve_path(root, "build"),
    app_package: "app",
    config_path: resolve_path(root, "moon.proton"),
    product_name: "Demo",
    identifier: "dev.proton.demo",
    version: "1.0.0",
    macos_version: "1.0.0",
    bundle_version: "1.0.0",
    targets: ["app"],
    output: root,
    build: false,
    base_dir: root,
    frontend_dist: None,
    entry_path: None,
    resources: [],
    icons: ["icon.png", icon],
    macos_icon: Some(icon),
    sign: false,
    notarize: false,
  }
  stage_macos_icon(plan, resources)
  let staged = @mbfs.read_file_to_string(
    resolve_path(resources, "AppIcon.icns"),
    encoding="utf8",
  ) catch {
    error => abort(@debug.render(@debug.to_repr(error)))
  }
  assert_eq(staged, "test-icns")
  assert_true(macos_info_plist(plan, "demo").contains("CFBundleIconFile"))
  remove_tree(icon)
  try stage_macos_icon(plan, resources) catch {
    PackagePlanError::MissingIcon(path~) => assert_eq(path, icon)
    _ => abort("expected missing macOS icon")
  } noraise {
    _ => abort("expected missing macOS icon failure")
  }
}

///|
test "macOS plist contains bundle identity and executable" {
  let plan = PackagePlan::{
    root: ".",
    workspace_root: ".",
    build_target_dir: "target/proton-package-build/dev-proton-demo",
    app_package: "app",
    config_path: "moon.proton",
    product_name: "Demo & App",
    identifier: "dev.proton.demo",
    version: "1.2.3",
    macos_version: "1.2.3",
    bundle_version: "1.2.3",
    targets: ["app"],
    output: "target",
    build: false,
    base_dir: ".",
    frontend_dist: None,
    entry_path: None,
    resources: [],
    icons: [],
    macos_icon: None,
    sign: false,
    notarize: false,
  }
  let plist = macos_info_plist(plan, "demo-app")
  assert_true(plist.contains("<string>Demo &amp; App</string>"))
  assert_true(plist.contains("<string>dev.proton.demo</string>"))
  assert_true(plist.contains("<string>demo-app</string>"))
  assert_true(plist.contains("<string>1.2.3</string>"))
  assert_false(plist.contains("CFBundleIconFile"))
}

///|
async test "macOS staged app promotion rolls back when staging is missing" {
  let root = "target/proton-package-macos-promotion"
  remove_tree(root)
  let destination = resolve_path(root, "Demo.app")
  let marker = resolve_path(destination, "Contents/old.txt")
  ensure_dir(path_parent(marker))
  write_text(marker, "old")
  try promote_staged_app(resolve_path(root, "missing.app"), destination) catch {
    _ => ()
  } noraise {
    _ => abort("expected staging promotion failure")
  }
  assert_true(@mbfs.path_exists(marker))
  assert_false(@mbfs.path_exists(destination + ".backup"))
}

///|
async test "macOS staged app promotion recovers an interrupted backup" {
  let root = "target/proton-package-macos-stale-backup"
  remove_tree(root)
  let destination = resolve_path(root, "Demo.app")
  let backup = destination + ".backup"
  let marker = resolve_path(backup, "Contents/old.txt")
  ensure_dir(path_parent(marker))
  write_text(marker, "old")
  try promote_staged_app(resolve_path(root, "missing.app"), destination) catch {
    _ => ()
  } noraise {
    _ => abort("expected staging promotion failure")
  }
  assert_true(@mbfs.path_exists(resolve_path(destination, "Contents/old.txt")))
  assert_false(@mbfs.path_exists(backup))
}

///|
async test "macOS notarization validates success and cleans failed upload" {
  guard is_macos_host() else { return }
  let root = resolve_path("target", "proton-package-notarization-flow")
  remove_tree(root)
  let tools = resolve_path(root, "tools")
  let app = resolve_path(root, "Demo.app")
  let log = resolve_path(root, "commands.log")
  for dir in [tools, resolve_path(app, "Contents")] {
    ensure_dir(dir)
  }
  let xcrun = resolve_path(tools, "xcrun")
  let spctl = resolve_path(tools, "spctl")
  let script = "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"" + log + "\"\nexit 0\n"
  for path in [xcrun, spctl] {
    write_text(path, script)
    @async_fs.chmod(path, 0o755) catch {
      error => abort(@debug.render(@debug.to_repr(error)))
    }
  }
  let old_path = @sys.get_env_var("PATH")
  let old_profile = @sys.get_env_var("PROTON_NOTARY_PROFILE")
  defer restore_package_env("PATH", old_path)
  defer restore_package_env("PROTON_NOTARY_PROFILE", old_profile)
  @sys.set_env_var("PATH", tools + ":" + old_path.unwrap_or(""))
  @sys.set_env_var("PROTON_NOTARY_PROFILE", "test-profile")
  let plan = PackagePlan::{
    root,
    workspace_root: root,
    build_target_dir: resolve_path(root, "build"),
    app_package: "app",
    config_path: resolve_path(root, "moon.proton"),
    product_name: "Demo",
    identifier: "dev.proton.demo",
    version: "1.0.0",
    macos_version: "1.0.0",
    bundle_version: "1.0.0",
    targets: ["app"],
    output: root,
    build: false,
    base_dir: root,
    frontend_dist: None,
    entry_path: None,
    resources: [],
    icons: [],
    macos_icon: None,
    sign: true,
    notarize: true,
  }
  notarize_macos_app(plan, app)
  let commands = @mbfs.read_file_to_string(log, encoding="utf8") catch {
    error => abort(@debug.render(@debug.to_repr(error)))
  }
  let archive = resolve_path(root, ".demo.notary.zip")
  assert_eq(
    commands,
    "notarytool submit " +
    archive +
    " --keychain-profile test-profile --wait\n" +
    "stapler staple " +
    app +
    "\n" +
    "stapler validate " +
    app +
    "\n" +
    "--assess --type execute --verbose=4 " +
    app +
    "\n",
  )
  assert_false(@mbfs.path_exists(archive))
  write_text(log, "")
  let failing_script = "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"" +
    log +
    "\"\nif [ \"$1\" = \"notarytool\" ]; then exit 42; fi\nexit 0\n"
  write_text(xcrun, failing_script)
  try notarize_macos_app(plan, app) catch {
    MacosSigningError::ToolFailure(stage~, detail~) => {
      assert_true(stage.contains("notarytool submit"))
      assert_true(detail.contains("42"))
    }
    _ => abort("expected notarization tool failure")
  } noraise {
    _ => abort("expected notarization submission failure")
  }
  let failed_commands = @mbfs.read_file_to_string(log, encoding="utf8") catch {
    error => abort(@debug.render(@debug.to_repr(error)))
  }
  assert_eq(
    failed_commands,
    "notarytool submit " + archive + " --keychain-profile test-profile --wait\n",
  )
  assert_false(@mbfs.path_exists(archive))
}

///|
async test "release executable lookup stays inside package target dir" {
  let root = "target/proton-package-executable-lookup"
  remove_tree(root)
  let package_target = resolve_path(root, "package-target")
  let unrelated = resolve_path(
    root, "workspace/native/release/build/other/app.exe",
  )
  ensure_dir(path_parent(unrelated))
  write_text(unrelated, "wrong")
  let plan = PackagePlan::{
    root,
    workspace_root: resolve_path(root, "workspace"),
    build_target_dir: package_target,
    app_package: "app",
    config_path: resolve_path(root, "moon.proton"),
    product_name: "Demo",
    identifier: "dev.proton.demo",
    version: "1.0.0",
    macos_version: "1.0.0",
    bundle_version: "1.0.0",
    targets: ["app"],
    output: resolve_path(root, "output"),
    build: false,
    base_dir: root,
    frontend_dist: None,
    entry_path: None,
    resources: [],
    icons: [],
    macos_icon: None,
    sign: false,
    notarize: false,
  }
  @debug.assert_eq(find_release_executable(plan), None)
  let expected = resolve_path(
    package_target, "native/release/build/vendor/app/app.exe",
  )
  ensure_dir(path_parent(expected))
  write_text(expected, "right")
  match find_release_executable(plan) {
    Some(actual) =>
      assert_eq(normalize_slashes(actual), normalize_slashes(expected))
    None => abort("expected release executable")
  }
}

///|
async test "active runtime rejects another platform" {
  let root = "target/proton-package-runtime-platform"
  remove_tree(root)
  ensure_dir(resolve_path(root, ".proton"))
  let old_dist = @sys.get_env_var("PROTON_NATIVE_DIST")
  @sys.unset_env_var("PROTON_NATIVE_DIST")
  defer restore_package_env("PROTON_NATIVE_DIST", old_dist)
  let expected = @cef.current_platform_id()
  let other = if expected == "win32-x64" { "darwin-arm64" } else { "win32-x64" }
  let manifest = Json::object({
    "platform": Json::string(other),
    "dist": Json::string("runtime"),
  }).stringify()
  write_text(resolve_path(root, ".proton/runtime.json"), manifest)
  try read_active_runtime(resolve_path(root, ".")) catch {
    PackageRuntimeError::PlatformMismatch(
      expected=actual_expected,
      actual=actual_platform
    ) => {
      assert_eq(actual_expected, expected)
      assert_eq(actual_platform, other)
    }
    _ => abort("expected platform mismatch")
  } noraise {
    _ => abort("expected platform mismatch")
  }
}

///|
async test "Windows portable staging flattens runtime bin beside app executable" {
  let root = "target/proton-package-windows-layout"
  let output = resolve_path(root, "output")
  remove_tree(root)
  let runtime = prepare_windows_test_runtime(root)
  let executable = resolve_path(root, "demo.exe")
  let config = resolve_path(root, "moon.proton")
  for item in [(executable, "exe"), (config, "config")] {
    let (path, text) = item
    write_windows_test_file(path, text)
  }
  let plan = PackagePlan::{
    root,
    workspace_root: root,
    build_target_dir: resolve_path(root, "package-build"),
    app_package: "app",
    config_path: config,
    product_name: "Demo App",
    identifier: "dev.proton.demo",
    version: "1.0.0",
    macos_version: "1.0.0",
    bundle_version: "1.0.0",
    targets: ["app"],
    output,
    build: false,
    base_dir: root,
    frontend_dist: None,
    entry_path: None,
    resources: [],
    icons: [],
    macos_icon: None,
    sign: false,
    notarize: false,
  }
  stage_windows_portable_with_options(
    plan,
    executable,
    runtime,
    default_windows_sign_tool(),
    None,
    false,
  )
  let portable = resolve_path(output, "demo-app")
  assert_true(@mbfs.path_exists(resolve_path(portable, "demo-app.exe")))
  assert_true(@mbfs.path_exists(resolve_path(portable, "proton.dll")))
  assert_true(@mbfs.path_exists(resolve_path(portable, "cef_process.exe")))
  assert_true(@mbfs.path_exists(resolve_path(portable, "libcef.dll")))
  assert_true(@mbfs.path_exists(resolve_path(portable, "Resources/icudtl.dat")))
  assert_false(@mbfs.path_exists(resolve_path(portable, "bin/proton.dll")))
}
