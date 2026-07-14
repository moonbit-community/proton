///|
test "parse package args accepts repeated targets and overrides" {
  let raw = match
    parse_package_args([
      "desktop", "--target", "app", "--target", "zip", "--output", "dist", "--no-build",
      "--dry-run",
    ]) {
    Ok(raw) => raw
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  assert_eq(raw.app_package, "desktop")
  @debug.assert_eq(raw.targets, ["app", "zip"])
  @debug.assert_eq(raw.output, Some("dist"))
  assert_false(raw.build)
  assert_true(raw.dry_run)
}

///|
test "parse package args rejects unsupported target" {
  match parse_package_args(["--target", "dmg"]) {
    Ok(_) => abort("expected unsupported target")
    Err(UsageError(message, _)) =>
      assert_eq(message, "unsupported package target: dmg")
    Err(_) => abort("expected usage error")
  }
}

///|
test "notarize implies signing" {
  let raw = match parse_package_args(["--notarize", "--dry-run"]) {
    Ok(raw) => raw
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  assert_true(raw.sign)
  assert_true(raw.notarize)
  assert_true(raw.dry_run)
}

///|
test "sign does not require notarization" {
  let raw = match parse_package_args(["--sign"]) {
    Ok(raw) => raw
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
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
  let raw = match parse_package_args([]) {
    Ok(raw) => raw
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  match build_package_plan(raw, "moon.proton", project) {
    Ok(_) => abort("expected missing bundle error")
    Err(CommandError(message)) =>
      assert_eq(message, "bundle config is required for proton package")
    Err(_) => abort("expected command error")
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
  let raw = match parse_package_args([]) {
    Ok(raw) => raw
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  let plan = match build_package_plan(raw, "moon.proton", project) {
    Ok(plan) => plan
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
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
test "package executable name is filesystem safe" {
  assert_eq(package_executable_name("My Proton App!"), "my-proton-app")
  assert_eq(package_executable_name("  ---  "), "proton-app")
}

///|
test "macOS package metadata validation rejects unsafe values" {
  match validate_product_name("Demo/App") {
    Ok(_) => abort("expected unsafe product name")
    Err(CommandError(message)) =>
      assert_true(message.contains("path-unsafe character"))
    Err(_) => abort("expected command error")
  }
  match validate_product_name("Demo\nApp") {
    Ok(_) => abort("expected control character error")
    Err(CommandError(message)) =>
      assert_true(message.contains("ASCII control character"))
    Err(_) => abort("expected command error")
  }
  match validate_bundle_identifier("demo") {
    Ok(_) => abort("expected reverse-DNS identifier error")
    Err(CommandError(message)) =>
      assert_true(message.contains("reverse-DNS bundle identifier"))
    Err(_) => abort("expected command error")
  }
  match validate_bundle_identifier("com.example.bad_value") {
    Ok(_) => abort("expected identifier character error")
    Err(CommandError(message)) =>
      assert_true(message.contains("unsupported character"))
    Err(_) => abort("expected command error")
  }
}

///|
test "macOS version normalizes semantic prerelease to plist versions" {
  let old_build = @sys.get_env_var("PROTON_MACOS_BUILD_NUMBER")
  @sys.unset_env_var("PROTON_MACOS_BUILD_NUMBER")
  defer restore_package_env("PROTON_MACOS_BUILD_NUMBER", old_build)
  match validate_macos_version("1.2.3-beta.1") {
    Ok((short_version, bundle_version)) => {
      assert_eq(short_version, "1.2.3")
      assert_eq(bundle_version, "1.2.3")
    }
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  match validate_macos_version("1.2.3+release.4") {
    Ok((short_version, bundle_version)) => {
      assert_eq(short_version, "1.2.3")
      assert_eq(bundle_version, "1.2.3")
    }
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  @sys.set_env_var("PROTON_MACOS_BUILD_NUMBER", "42.7")
  match validate_macos_version("1.2.3") {
    Ok((short_version, bundle_version)) => {
      assert_eq(short_version, "1.2.3")
      assert_eq(bundle_version, "42.7")
    }
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  @sys.set_env_var("PROTON_MACOS_BUILD_NUMBER", "42.beta")
  match validate_macos_version("1.2.3") {
    Ok(_) => abort("expected invalid build number error")
    Err(CommandError(message)) =>
      assert_true(message.contains("PROTON_MACOS_BUILD_NUMBER"))
    Err(_) => abort("expected command error")
  }
  @sys.unset_env_var("PROTON_MACOS_BUILD_NUMBER")
  match validate_macos_version("1.two.3") {
    Ok(_) => abort("expected numeric version error")
    Err(CommandError(message)) =>
      assert_true(message.contains("must be numeric"))
    Err(_) => abort("expected command error")
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
  match validate_macos_signing_identity("-", notarize=false) {
    Ok(_) => abort("expected ad-hoc signing rejection")
    Err(_) => ()
  }
  @sys.set_env_var("PROTON_MACOS_ALLOW_ADHOC", "yes")
  assert_true(macos_adhoc_signing_allowed())
  match validate_macos_signing_identity("-", notarize=false) {
    Ok(is_adhoc) => assert_true(is_adhoc)
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  match
    validate_macos_signing_identity("Apple Development: Example", notarize=true) {
    Ok(is_adhoc) => assert_false(is_adhoc)
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  match validate_macos_signing_identity("-", notarize=true) {
    Ok(_) => abort("expected ad-hoc notarization rejection")
    Err(CommandError(message)) =>
      assert_true(message.contains("Developer ID Application"))
    Err(_) => abort("expected command error")
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
  match remove_tree(missing) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  match
    require_macos_codesign_targets([
      MacosCodeSignTarget::{
        path: missing,
        runtime_options: false,
        deep: false,
      },
    ]) {
    Ok(_) => abort("expected missing signing target failure")
    Err(CommandError(message)) => {
      assert_true(message.contains("required macOS signing target is missing"))
      assert_true(message.contains(missing))
    }
    Err(_) => abort("expected command error")
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
  match remove_tree(root) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  let resources = resolve_path(root, "Resources")
  let icon = resolve_path(root, "Demo.ICNS")
  match ensure_dir(resources) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  match write_text(icon, "test-icns") {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
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
  match stage_macos_icon(plan, resources) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  let staged = @mbfs.read_file_to_string(
    resolve_path(resources, "AppIcon.icns"),
    encoding="utf8",
  ) catch {
    error => abort(@debug.render(@debug.to_repr(error)))
  }
  assert_eq(staged, "test-icns")
  assert_true(macos_info_plist(plan, "demo").contains("CFBundleIconFile"))
  match remove_tree(icon) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  match stage_macos_icon(plan, resources) {
    Ok(_) => abort("expected missing macOS icon failure")
    Err(CommandError(message)) =>
      assert_true(message.contains("icon is missing"))
    Err(_) => abort("expected command error")
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
  match remove_tree(root) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  let destination = resolve_path(root, "Demo.app")
  let marker = resolve_path(destination, "Contents/old.txt")
  match ensure_dir(path_parent(marker)) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  match write_text(marker, "old") {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  match promote_staged_app(resolve_path(root, "missing.app"), destination) {
    Ok(_) => abort("expected staging promotion failure")
    Err(_) => ()
  }
  assert_true(@mbfs.path_exists(marker))
  assert_false(@mbfs.path_exists(destination + ".backup"))
}

///|
async test "macOS staged app promotion recovers an interrupted backup" {
  let root = "target/proton-package-macos-stale-backup"
  match remove_tree(root) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  let destination = resolve_path(root, "Demo.app")
  let backup = destination + ".backup"
  let marker = resolve_path(backup, "Contents/old.txt")
  match ensure_dir(path_parent(marker)) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  match write_text(marker, "old") {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  match promote_staged_app(resolve_path(root, "missing.app"), destination) {
    Ok(_) => abort("expected staging promotion failure")
    Err(_) => ()
  }
  assert_true(@mbfs.path_exists(resolve_path(destination, "Contents/old.txt")))
  assert_false(@mbfs.path_exists(backup))
}

///|
async test "macOS notarization validates success and cleans failed upload" {
  guard is_macos_host() else { return }
  let root = resolve_path("target", "proton-package-notarization-flow")
  match remove_tree(root) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  let tools = resolve_path(root, "tools")
  let app = resolve_path(root, "Demo.app")
  let log = resolve_path(root, "commands.log")
  for dir in [tools, resolve_path(app, "Contents")] {
    match ensure_dir(dir) {
      Ok(_) => ()
      Err(error) => abort(@debug.render(@debug.to_repr(error)))
    }
  }
  let xcrun = resolve_path(tools, "xcrun")
  let spctl = resolve_path(tools, "spctl")
  let script = "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"" + log + "\"\nexit 0\n"
  for path in [xcrun, spctl] {
    match write_text(path, script) {
      Ok(_) => ()
      Err(error) => abort(@debug.render(@debug.to_repr(error)))
    }
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
  match notarize_macos_app(plan, app) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
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
  match write_text(log, "") {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  let failing_script = "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"" +
    log +
    "\"\nif [ \"$1\" = \"notarytool\" ]; then exit 42; fi\nexit 0\n"
  match write_text(xcrun, failing_script) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  match notarize_macos_app(plan, app) {
    Ok(_) => abort("expected notarization submission failure")
    Err(CommandError(message)) => {
      assert_true(message.contains("notarytool submit"))
      assert_true(message.contains("42"))
    }
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
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
test "macOS notarization reports operation and cleanup failures" {
  match
    finish_macos_notarization(
      Err(CommandError("submit failed")),
      Err(CommandError("cleanup failed")),
      ".demo.notary.zip",
    ) {
    Ok(_) => abort("expected combined notarization failure")
    Err(CommandError(message)) => {
      assert_true(message.contains(".demo.notary.zip"))
      assert_true(message.contains("submit failed"))
      assert_true(message.contains("cleanup failed"))
    }
    Err(_) => abort("expected command error")
  }
}

///|
async test "release executable lookup stays inside package target dir" {
  let root = "target/proton-package-executable-lookup"
  match remove_tree(root) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  let package_target = resolve_path(root, "package-target")
  let unrelated = resolve_path(
    root, "workspace/native/release/build/other/app.exe",
  )
  match ensure_dir(path_parent(unrelated)) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  match write_text(unrelated, "wrong") {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
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
  match ensure_dir(path_parent(expected)) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  match write_text(expected, "right") {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  @debug.assert_eq(find_release_executable(plan), Some(expected))
}

///|
async test "active runtime rejects another platform" {
  let root = "target/proton-package-runtime-platform"
  match remove_tree(root) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  match ensure_dir(resolve_path(root, ".proton")) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  let old_dist = @sys.get_env_var("PROTON_NATIVE_DIST")
  @sys.unset_env_var("PROTON_NATIVE_DIST")
  defer restore_package_env("PROTON_NATIVE_DIST", old_dist)
  let expected = @cef.current_platform_id()
  let other = if expected == "win32-x64" { "darwin-arm64" } else { "win32-x64" }
  let manifest = Json::object({
    "platform": Json::string(other),
    "dist": Json::string("runtime"),
  }).stringify()
  match write_text(resolve_path(root, ".proton/runtime.json"), manifest) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  match read_active_runtime(resolve_path(root, ".")) {
    Ok(_) => abort("expected platform mismatch")
    Err(CommandError(message)) => {
      assert_true(message.contains("active Proton runtime platform mismatch"))
      assert_true(message.contains("expected " + expected))
      assert_true(message.contains("got " + other))
    }
    Err(_) => abort("expected command error")
  }
}

///|
async test "Windows portable staging flattens runtime bin beside app executable" {
  let root = "target/proton-package-windows-layout"
  let runtime = resolve_path(root, "runtime")
  let output = resolve_path(root, "output")
  match remove_tree(root) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  for dir in [resolve_path(runtime, "bin"), resolve_path(runtime, "Resources")] {
    match ensure_dir(dir) {
      Ok(_) => ()
      Err(error) => abort(@debug.render(@debug.to_repr(error)))
    }
  }
  let executable = resolve_path(root, "demo.exe")
  let config = resolve_path(root, "moon.proton")
  for
    item in [
      (resolve_path(runtime, "bin/proton.dll"), "dll"),
      (resolve_path(runtime, "bin/cef_process.exe"), "helper"),
      (resolve_path(runtime, "bin/libcef.dll"), "cef"),
      (resolve_path(runtime, "Resources/icudtl.dat"), "data"),
      (executable, "exe"),
      (config, "config"),
    ] {
    let (path, text) = item
    match write_text(path, text) {
      Ok(_) => ()
      Err(error) => abort(@debug.render(@debug.to_repr(error)))
    }
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
  match stage_windows_portable(plan, executable, runtime) {
    Ok(_) => ()
    Err(error) => abort(@debug.render(@debug.to_repr(error)))
  }
  let portable = resolve_path(output, "demo-app")
  assert_true(@mbfs.path_exists(resolve_path(portable, "demo-app.exe")))
  assert_true(@mbfs.path_exists(resolve_path(portable, "proton.dll")))
  assert_true(@mbfs.path_exists(resolve_path(portable, "cef_process.exe")))
  assert_true(@mbfs.path_exists(resolve_path(portable, "libcef.dll")))
  assert_true(@mbfs.path_exists(resolve_path(portable, "Resources/icudtl.dat")))
  assert_false(@mbfs.path_exists(resolve_path(portable, "bin/proton.dll")))
}
