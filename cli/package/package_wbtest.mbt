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
    targets: ["app"],
    output: "target",
    build: false,
    base_dir: ".",
    frontend_dist: None,
    entry_path: None,
    resources: [],
    icons: [],
    sign: false,
    notarize: false,
  }
  let plist = macos_info_plist(plan, "demo-app")
  assert_true(plist.contains("<string>Demo &amp; App</string>"))
  assert_true(plist.contains("<string>dev.proton.demo</string>"))
  assert_true(plist.contains("<string>demo-app</string>"))
  assert_true(plist.contains("<string>1.2.3</string>"))
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
    targets: ["app"],
    output: resolve_path(root, "output"),
    build: false,
    base_dir: root,
    frontend_dist: None,
    entry_path: None,
    resources: [],
    icons: [],
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
    targets: ["app"],
    output,
    build: false,
    base_dir: root,
    frontend_dist: None,
    entry_path: None,
    resources: [],
    icons: [],
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
