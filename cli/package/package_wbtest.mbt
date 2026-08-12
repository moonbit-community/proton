///|
fn parse_package_args(args : Array[String]) -> RawPackageOptions raise {
  package_options_from_matches(command().parse(argv=args, env=Map([])))
}

///|
fn parse_package_matches(args : Array[String]) -> @argparse.Matches raise {
  command().parse(argv=args, env=Map([]))
}

///|
test "parse package args accepts repeated targets and overrides" {
  let raw = parse_package_args([
    "--package", "desktop", "--target", "app", "--target", "zip", "--target", "dmg",
    "--output", "dist", "--no-build", "--dry-run",
  ])
  @debug.assert_eq(raw.app_package, Some("desktop"))
  @debug.assert_eq(raw.targets, ["app", "zip", "dmg"])
  @debug.assert_eq(raw.output, Some("dist"))
  assert_false(raw.build)
  assert_false(raw.release)
  assert_true(raw.dry_run)
}

///|
test "parse package args enables release builds explicitly" {
  let raw = parse_package_args(["--release"])
  assert_true(raw.build)
  assert_true(raw.release)
}

///|
test "parse package args rejects unsupported target" {
  try parse_package_args(["--target", "msi"]) catch {
    PackageUsageError::UnsupportedTarget(target="msi") => ()
    _ => abort("expected unsupported target")
  } noraise {
    _ => abort("expected unsupported target")
  }
}

///|
test "updater revision is explicit, positive and full width" {
  assert_eq(updater_revision_from_matches(parse_package_matches([]), None), 0UL)
  let maximum = "18446744073709551615"
  let matches = parse_package_matches(["--updater-revision", maximum])
  assert_eq(
    updater_revision_from_matches(matches, None),
    18446744073709551615UL,
  )
  let no_revision = parse_package_matches([])
  try
    ignore(
      updater_revision_from_matches(
        no_revision,
        Some("https://example.com/releases"),
      ),
    )
  catch {
    MissingRevision => ()
    _ => abort("expected a missing updater revision")
  } noraise {
    _ => abort("expected the updater revision to be required")
  }
  for expected in ["0", "-1", "1.5", "not-a-number"] {
    let invalid = parse_package_matches(["--updater-revision", expected])
    try ignore(updater_revision_from_matches(invalid, None)) catch {
      InvalidRevision(value~) => assert_eq(value, expected)
      _ => abort("expected an invalid updater revision")
    } noraise {
      _ => abort("expected the updater revision to be rejected")
    }
  }
}

///|
async test "package plan accepts dmg only on macOS" {
  let project = @proton_config.ProjectConfig::new(
    ".",
    @proton_config.ProjectWindowConfig::new("Demo", 800, 600),
    @proton_config.ProjectEntry::Html("<main>demo</main>"),
    @proton_config.ProjectMetadata::new(
      "Demo",
      identifier=Some("dev.proton.demo"),
      version=Some("1.0.0"),
    ),
    bundle=Some(
      @proton_config.ProjectBundleConfig::new(active=true, targets=["dmg"]),
    ),
  )
  let raw = parse_package_args([])
  if is_macos_host() {
    let plan = build_package_plan(raw, "proton.project.json", project, 0UL)
    @debug.assert_eq(plan.targets, ["dmg"])
  } else {
    try build_package_plan(raw, "proton.project.json", project, 0UL) catch {
      PackagePlanError::UnsupportedTargetForPlatform(target="dmg", platform~) =>
        assert_true(platform != "")
      _ => abort("expected platform-specific target error")
    } noraise {
      _ => abort("expected dmg to be rejected outside macOS")
    }
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
async test "package plan requires active bundle" {
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
  try build_package_plan(raw, "proton.project.json", project, 0UL) catch {
    PackageConfigError::BundleMissing => ()
    _ => abort("expected missing bundle error")
  } noraise {
    _ => abort("expected missing bundle error")
  }
}

///|
async test "package plan uses the host defaults" {
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
  let plan = build_package_plan(raw, "proton.project.json", project, 0UL)
  let expected_targets = match current_package_host() {
    Linux => ["appimage"]
    Macos | Windows => ["app", "zip"]
  }
  @debug.assert_eq(plan.targets, expected_targets)
  assert_eq(plan.identifier, "dev.proton.demo")
  assert_eq(plan.version, "1.0.0")
  assert_false(plan.release)
  assert_true(
    normalize_slashes(plan.build_target_dir).has_suffix(
      "/target/proton-package-build/dev-proton-demo",
    ),
  )
  let release_plan = build_package_plan(
    parse_package_args(["--release"]),
    "proton.project.json",
    project,
    0UL,
  )
  assert_true(release_plan.release)
}

///|
async test "package plan stages every window file entry" {
  let root = @fsutil.resolve_path("target", "proton-package-window-entries")
  remove_tree(root)
  let main = @fsutil.resolve_path(root, "pages/main.html")
  let secondary = @fsutil.resolve_path(root, "standalone/settings.html")
  ensure_dir(@fsutil.path_parent(main))
  ensure_dir(@fsutil.path_parent(secondary))
  write_text(main, "<main>Main</main>")
  write_text(secondary, "<main>Settings</main>")
  let project = @proton_config.ProjectConfig::new(
    root,
    @proton_config.ProjectWindowConfig::new("Demo", 800, 600),
    @proton_config.ProjectEntry::Asset(main),
    @proton_config.ProjectMetadata::new(
      "Demo",
      identifier=Some("dev.proton.window-entries"),
      version=Some("1.0.0"),
    ),
    windows=[
      @proton_config.ProjectAppWindowConfig::new(
        "settings",
        @proton_config.ProjectWindowConfig::new("Settings", 480, 360),
        @proton_config.ProjectEntry::File(secondary),
      ),
    ],
    bundle=Some(@proton_config.ProjectBundleConfig::new(active=true)),
  )
  let plan = build_package_plan(
    parse_package_args([]),
    @fsutil.resolve_path(root, "proton.project.json"),
    project,
    0UL,
  )
  assert_eq(plan.entry_paths, [main, secondary])
  let destination = @fsutil.resolve_path(root, "staged")
  ensure_dir(destination)
  stage_project_inputs(plan, destination)
  assert_true(
    @mbfs.path_exists(@fsutil.resolve_path(destination, "pages/main.html")),
  )
  assert_true(
    @mbfs.path_exists(
      @fsutil.resolve_path(destination, "standalone/settings.html"),
    ),
  )
}

///|
async test "configured signing binaries resolve through staged resources" {
  let root = @fsutil.resolve_path("target", "proton-package-sign-binaries")
  remove_tree(root)
  let binary = @fsutil.resolve_path(root, "bin/worker")
  ensure_dir(@fsutil.path_parent(binary))
  write_text(binary, "binary")
  let project = @proton_config.ProjectConfig::new(
    root,
    @proton_config.ProjectWindowConfig::new("Demo", 800, 600),
    @proton_config.ProjectEntry::Html("<main>demo</main>"),
    @proton_config.ProjectMetadata::new(
      "Demo",
      identifier=Some("dev.proton.sign-binaries"),
      version=Some("1.0.0"),
    ),
    bundle=Some(
      @proton_config.ProjectBundleConfig::new(
        active=true,
        resources=[binary],
        sign=Some(@proton_config.ProjectSignConfig::new(binaries=[binary])),
      ),
    ),
  )
  let plan = build_package_plan(
    parse_package_args([]),
    @fsutil.resolve_path(root, "proton.project.json"),
    project,
    0UL,
  )
  let resource_root = @fsutil.resolve_path(root, "staged resources")
  ensure_dir(resource_root)
  stage_project_inputs(plan, resource_root)
  let staged_binary = @fsutil.resolve_path(resource_root, "bin/worker")
  assert_true(@fsutil.path_is_file(staged_binary))
  @debug.assert_eq(plan.sign_binary_targets(resource_root), [staged_binary])
}

///|
async test "package plan uses configured backend module and package" {
  let base_dir = @fsutil.resolve_path("target", "proton package module paths")
  let backend_path = @fsutil.resolve_path(base_dir, "modules/backend app")
  let project = @proton_config.ProjectConfig::new(
    base_dir,
    @proton_config.ProjectWindowConfig::new("Demo", 800, 600),
    @proton_config.ProjectEntry::Html("<main>demo</main>"),
    @proton_config.ProjectMetadata::new(
      "Demo",
      identifier=Some("dev.proton.module-paths"),
      version=Some("1.0.0"),
    ),
    backend=Some(
      @proton_config.ProjectBackendConfig::new(backend_path, "desktop"),
    ),
    bundle=Some(@proton_config.ProjectBundleConfig::new(active=true)),
  )
  let configured = build_package_plan(
    parse_package_args([]),
    @fsutil.resolve_path(base_dir, "proton.project.json"),
    project,
    0UL,
  )
  assert_eq(configured.root, backend_path)
  assert_eq(configured.app_package, "desktop")
  let overridden = build_package_plan(
    parse_package_args(["--package", "custom"]),
    @fsutil.resolve_path(base_dir, "proton.project.json"),
    project,
    0UL,
  )
  assert_eq(overridden.app_package, "custom")
}

///|
#cfg(not(platform="windows"))
test "macOS package paths normalize absolute and relative inputs" {
  let base = @fsutil.resolve_path("target", "proton package path base")
  assert_eq(@fsutil.resolve_path(base, "/"), "/")
  assert_eq(
    @fsutil.resolve_path(base, "/tmp/proton absolute path"),
    "/tmp/proton absolute path",
  )
  assert_eq(
    @fsutil.resolve_path(base, "relative/file.txt"),
    base + "/relative/file.txt",
  )
  assert_eq(
    @fsutil.resolve_path(base, ".proton/runtime.json"),
    base + "/.proton/runtime.json",
  )
  assert_eq(
    @fsutil.resolve_path(base, "directory with spaces/file.txt"),
    base + "/directory with spaces/file.txt",
  )
  assert_eq(
    @fsutil.resolve_path(base, "../sibling"),
    @fsutil.resolve_path(@fsutil.path_parent(base), "sibling"),
  )
  assert_eq(
    @fsutil.resolve_path(base, "nested\\child.txt"),
    base + "/nested\\child.txt",
  )
  assert_eq(
    @fsutil.resolve_path(base, "\\tmp\\proton path"),
    base + "/\\tmp\\proton path",
  )
}

///|
#cfg(not(platform="windows"))
async test "macOS ensure_dir recursively creates absolute paths with spaces" {
  let root = @fsutil.resolve_path("target", "proton package ensure dir")
  remove_tree(root)
  let nested = @fsutil.resolve_path(root, "parent with spaces/child/grandchild")
  ensure_dir(nested)
  assert_true(@fsutil.path_is_dir(nested))
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
  let old_build = @env.get_env_var("PROTON_MACOS_BUILD_NUMBER")
  @env.unset_env_var("PROTON_MACOS_BUILD_NUMBER")
  defer restore_package_env("PROTON_MACOS_BUILD_NUMBER", old_build)
  let (short_version, bundle_version) = validate_macos_version("1.2.3-beta.1")
  assert_eq(short_version, "1.2.3")
  assert_eq(bundle_version, "1.2.3")
  let (short_version, bundle_version) = validate_macos_version(
    "1.2.3+release.4",
  )
  assert_eq(short_version, "1.2.3")
  assert_eq(bundle_version, "1.2.3")
  @env.set_env_var("PROTON_MACOS_BUILD_NUMBER", "42.7")
  let (short_version, bundle_version) = validate_macos_version("1.2.3")
  assert_eq(short_version, "1.2.3")
  assert_eq(bundle_version, "42.7")
  @env.set_env_var("PROTON_MACOS_BUILD_NUMBER", "42.beta")
  try validate_macos_version("1.2.3") catch {
    PackagePlanError::InvalidVersion(reason~, ..) =>
      assert_true(reason.contains("PROTON_MACOS_BUILD_NUMBER"))
    _ => abort("expected invalid build number")
  } noraise {
    _ => abort("expected invalid build number error")
  }
  @env.unset_env_var("PROTON_MACOS_BUILD_NUMBER")
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
    identifier=None,
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
  let old = @env.get_env_var("PROTON_MACOS_ALLOW_ADHOC")
  defer restore_package_env("PROTON_MACOS_ALLOW_ADHOC", old)
  @env.unset_env_var("PROTON_MACOS_ALLOW_ADHOC")
  assert_false(macos_adhoc_signing_allowed())
  try validate_macos_signing_identity("-", notarize=false) catch {
    MacosSigningError::InvalidConfiguration(_) => ()
    _ => abort("expected ad-hoc signing rejection")
  } noraise {
    _ => abort("expected ad-hoc signing rejection")
  }
  @env.set_env_var("PROTON_MACOS_ALLOW_ADHOC", "yes")
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
  @env.set_env_var("PROTON_MACOS_ALLOW_ADHOC", "false")
  assert_false(macos_adhoc_signing_allowed())
}

///|
test "macOS CEF process signing preserves hardened runtime and identifier" {
  let args = macos_codesign_args(
    "Developer ID Application: Example",
    "cef_process",
    runtime_options=true,
    deep=false,
    entitlements=None,
    identifier=Some("cef_process"),
  )
  assert_true(args.contains("--timestamp"))
  assert_true(args.contains("--options"))
  assert_true(args.contains("runtime"))
  assert_true(args.contains("-i"))
  assert_true(args.contains("cef_process"))
  assert_false(args.contains("--deep"))
  assert_false(args.contains("--entitlements"))
}

///|
async test "macOS signing rejects a missing required target" {
  let missing = @fsutil.resolve_path(
    "target", "proton-package-missing-signing-target",
  )
  remove_tree(missing)
  try
    require_macos_codesign_targets([
      MacosCodeSignTarget::{
        path: missing,
        runtime_options: false,
        entitlements: false,
        identifier: None,
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
test "release project config disables only the top-level debug field" {
  let source =
    #|{
    #|  "product_name": "MoonBit 桌面应用",
    #|  "window": {
    #|    "title": "debug = true",
    #|    "width": 800,
    #|    "height": 600
    #|  },
    #|  "entry": {
    #|    "kind": "html",
    #|    "value": "<p>debug = true</p>"
    #|  },
    #|  "debug": true,
    #|  "bundle": {
    #|    "active": true
    #|  }
    #|}
  let release = release_project_config_text(source)
  assert_true(release.contains("\"title\": \"debug = true\""))
  assert_true(release.contains("\"value\": \"<p>debug = true</p>\""))
  let json = @json.parse(release) catch { error => abort(error.to_string()) }
  guard json is { "debug": false, .. } else {
    abort("expected disabled top-level debug field")
  }
}

///|
test "release project config preserves an already disabled or absent debug field" {
  let disabled = "{\"window\":{\"title\":\"Demo\"},\"debug\":false}\n"
  assert_eq(release_project_config_text(disabled), disabled)
  let absent = "{\"window\":{\"title\":\"Demo\"}}\n"
  assert_eq(release_project_config_text(absent), absent)
}

///|
async test "macOS icon selection stages icns and rejects a missing source" {
  let root = @fsutil.resolve_path("target", "proton-package-macos-icon")
  remove_tree(root)
  let resources = @fsutil.resolve_path(root, "Resources")
  let icon = @fsutil.resolve_path(root, "Demo.ICNS")
  ensure_dir(resources)
  write_text(icon, "test-icns")
  match first_macos_icon(["icon.png", icon]) {
    Some(selected) => assert_eq(selected, icon)
    None => abort("expected .icns icon selection")
  }
  let plan = PackagePlan::{
    root,
    workspace_root: root,
    build_target_dir: @fsutil.resolve_path(root, "build"),
    app_package: "app",
    config_path: @fsutil.resolve_path(root, "proton.project.json"),
    product_name: "Demo",
    identifier: "dev.proton.demo",
    version: "1.0.0",
    macos_version: "1.0.0",
    bundle_version: "1.0.0",
    update_revision: 0UL,
    targets: ["app"],
    output: root,
    build: false,
    release: false,
    base_dir: root,
    frontend_dist: None,
    entry_paths: [],
    sign_binaries: [],
    resources: [],
    icons: ["icon.png", icon],
    url_schemes: [],
    document_types: [],
    macos_icon: Some(icon),
    sign: false,
    notarize: false,
  }
  stage_macos_icon(plan, resources)
  let staged = @mbfs.read_file_to_string(
    @fsutil.resolve_path(resources, "AppIcon.icns"),
    encoding="utf8",
  ) catch {
    error => abort(@debug.render(Repr(error)))
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
    config_path: "proton.project.json",
    product_name: "Demo & App",
    identifier: "dev.proton.demo",
    version: "1.2.3",
    macos_version: "1.2.3",
    bundle_version: "1.2.3",
    update_revision: 42UL,
    targets: ["app"],
    output: "target",
    build: false,
    release: false,
    base_dir: ".",
    frontend_dist: None,
    entry_paths: [],
    sign_binaries: [],
    resources: [],
    icons: [],
    url_schemes: ["devtoys"],
    document_types: [
      @proton_config.ProjectDocumentType::new(
        "Text",
        ["txt", "md"],
        role="Editor",
      ),
    ],
    macos_icon: None,
    sign: false,
    notarize: false,
  }
  let plist = macos_info_plist(plan, "demo-app")
  assert_true(plist.contains("<string>Demo &amp; App</string>"))
  assert_true(plist.contains("<string>dev.proton.demo</string>"))
  assert_true(plist.contains("<string>demo-app</string>"))
  assert_true(plist.contains("<string>1.2.3</string>"))
  assert_true(
    plist.contains("<key>ProtonUpdateRevision</key><string>42</string>"),
  )
  assert_true(plist.contains("CFBundleURLTypes"))
  assert_true(plist.contains("<string>devtoys</string>"))
  assert_true(plist.contains("CFBundleDocumentTypes"))
  assert_true(plist.contains("<string>Editor</string>"))
  assert_true(plist.contains("<string>md</string>"))
  assert_false(plist.contains("CFBundleIconFile"))
}

///|
async test "package manifest records launch metadata" {
  let root = "target/proton-package-launch-metadata"
  ensure_dir(root)
  let plan = PackagePlan::{
    root: ".",
    workspace_root: ".",
    build_target_dir: "target/proton-package-build/dev-proton-demo",
    app_package: "app",
    config_path: "proton.project.json",
    product_name: "Demo",
    identifier: "dev.proton.demo",
    version: "1.2.3",
    macos_version: "1.2.3",
    bundle_version: "1.2.3",
    update_revision: 0UL,
    targets: ["app"],
    output: "target",
    build: false,
    release: false,
    base_dir: ".",
    frontend_dist: None,
    entry_paths: [],
    sign_binaries: [],
    resources: [],
    icons: [],
    url_schemes: ["devtoys"],
    document_types: [
      @proton_config.ProjectDocumentType::new(
        "Text",
        ["txt", "md"],
        role="Editor",
      ),
    ],
    macos_icon: None,
    sign: false,
    notarize: false,
  }
  write_package_manifest(plan, root, "macos-app")
  let manifest = @mbfs.read_file_to_string(
    @fsutil.resolve_path(root, "proton-package.json"),
    encoding="utf8",
  ) catch {
    error => abort(@debug.render(Repr(error)))
  }
  assert_true(manifest.contains("\"url_schemes\":[\"devtoys\"]"))
  assert_true(manifest.contains("\"extensions\":[\"txt\",\"md\"]"))
  assert_true(manifest.contains("\"role\":\"Editor\""))
}

///|
test "macOS package defines the complete CEF helper family" {
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
  let plan = PackagePlan::{
    root: ".",
    workspace_root: ".",
    build_target_dir: "target/proton-package-build/dev-proton-demo",
    app_package: "app",
    config_path: "proton.project.json",
    product_name: "Demo & App",
    identifier: "dev.proton.demo",
    version: "1.2.3",
    macos_version: "1.2.3",
    bundle_version: "42",
    update_revision: 42UL,
    targets: ["app"],
    output: "target",
    build: false,
    release: false,
    base_dir: ".",
    frontend_dist: None,
    entry_paths: [],
    sign_binaries: [],
    resources: [],
    icons: [],
    url_schemes: [],
    document_types: [],
    macos_icon: None,
    sign: false,
    notarize: false,
  }
  let helper = macos_helper_specs(plan.product_name, plan.identifier)[4]
  let plist = helper_info_plist(plan, helper)
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
async test "macOS ZIP uses the final app name without metadata entries" {
  guard is_macos_host() else { return }
  let root = @fsutil.resolve_path("target", "proton-package-macos-zip-layout")
  remove_tree(root)
  let plan = PackagePlan::{
    root,
    workspace_root: root,
    build_target_dir: @fsutil.resolve_path(root, "build"),
    app_package: "app",
    config_path: @fsutil.resolve_path(root, "proton.project.json"),
    product_name: "Demo App",
    identifier: "dev.proton.demo",
    version: "1.0.0",
    macos_version: "1.0.0",
    bundle_version: "1.0.0",
    update_revision: 0UL,
    targets: ["app", "zip"],
    output: root,
    build: false,
    release: false,
    base_dir: root,
    frontend_dist: None,
    sign_binaries: [],
    entry_paths: [],
    resources: [],
    icons: [],
    url_schemes: [],
    document_types: [],
    macos_icon: None,
    sign: false,
    notarize: false,
  }
  let app = macos_staging_app_path(plan)
  let payload = @fsutil.resolve_path(app, "Contents/Resources/payload.txt")
  ensure_dir(@fsutil.path_parent(payload))
  write_text(payload, "payload")
  let xattr_code = @process.run("xattr", [
    "-w", "com.proton.package-test", "value", payload,
  ]) catch {
    error => abort(@debug.render(Repr(error)))
  }
  assert_eq(xattr_code, 0)
  let archive = macos_zip_staging_path(plan)
  create_zip(app, archive)
  let (zipinfo_code, listing) = @process.collect_output_merged("zipinfo", [
    "-1", archive,
  ]) catch {
    error => abort(@debug.render(Repr(error)))
  }
  assert_eq(zipinfo_code, 0)
  let listing = listing.text() catch {
    error => abort(@debug.render(Repr(error)))
  }
  assert_true(listing.contains("Demo App.app/"))
  assert_false(listing.contains(".staging"))
  assert_false(listing.contains("__MACOSX"))
  assert_false(listing.contains("._"))
}

///|
async test "macOS staged app promotion rolls back when staging is missing" {
  let root = "target/proton-package-macos-promotion"
  remove_tree(root)
  let destination = @fsutil.resolve_path(root, "Demo.app")
  let marker = @fsutil.resolve_path(destination, "Contents/old.txt")
  ensure_dir(@fsutil.path_parent(marker))
  write_text(marker, "old")
  try
    promote_staged_artifacts([
      StagedArtifact::{
        staging: @fsutil.resolve_path(root, "missing.app"),
        destination,
      },
    ])
  catch {
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
  let destination = @fsutil.resolve_path(root, "Demo.app")
  let backup = destination + ".backup"
  let marker = @fsutil.resolve_path(backup, "Contents/old.txt")
  ensure_dir(@fsutil.path_parent(marker))
  write_text(marker, "old")
  try
    promote_staged_artifacts([
      StagedArtifact::{
        staging: @fsutil.resolve_path(root, "missing.app"),
        destination,
      },
    ])
  catch {
    _ => ()
  } noraise {
    _ => abort("expected staging promotion failure")
  }
  assert_true(
    @mbfs.path_exists(@fsutil.resolve_path(destination, "Contents/old.txt")),
  )
  assert_false(@mbfs.path_exists(backup))
}

///|
async test "macOS artifact promotion rolls back the complete output set" {
  let root = "target/proton-package-macos-transaction"
  remove_tree(root)
  let app = @fsutil.resolve_path(root, "Demo.app")
  let app_backup = app + ".backup"
  let staged_app = @fsutil.resolve_path(root, ".demo.staging.app")
  let dmg = @fsutil.resolve_path(root, "Demo.dmg")
  let staged_dmg = @fsutil.resolve_path(root, ".demo.staging.dmg")
  let staged_zip = @fsutil.resolve_path(root, ".demo.staging.app.zip")
  let invalid_zip = @fsutil.resolve_path(root, "missing/Demo.app.zip")
  let old_marker = @fsutil.resolve_path(app, "Contents/old.txt")
  let new_marker = @fsutil.resolve_path(staged_app, "Contents/new.txt")
  ensure_dir(@fsutil.path_parent(old_marker))
  ensure_dir(@fsutil.path_parent(new_marker))
  write_text(old_marker, "old")
  write_text(new_marker, "new")
  write_text(dmg, "old-dmg")
  write_text(staged_dmg, "new-dmg")
  write_text(staged_zip, "zip")
  try
    promote_staged_artifacts([
      StagedArtifact::{ staging: staged_app, destination: app },
      StagedArtifact::{ staging: staged_dmg, destination: dmg },
      StagedArtifact::{ staging: staged_zip, destination: invalid_zip },
    ])
  catch {
    _ => ()
  } noraise {
    _ => abort("expected multi-artifact promotion failure")
  }
  assert_true(@mbfs.path_exists(old_marker))
  assert_false(@mbfs.path_exists(@fsutil.resolve_path(app, "Contents/new.txt")))
  assert_false(@mbfs.path_exists(app_backup))
  let restored_dmg = @mbfs.read_file_to_string(dmg, encoding="utf8") catch {
    error => abort(@debug.render(Repr(error)))
  }
  assert_eq(restored_dmg, "old-dmg")
  assert_false(@mbfs.path_exists(dmg + ".backup"))
  assert_true(@mbfs.path_exists(staged_zip))
}

///|
async test "macOS notarization validates success and cleans failed upload" {
  guard is_macos_host() else { return }
  let root = @fsutil.resolve_path("target", "proton-package-notarization-flow")
  remove_tree(root)
  let tools = @fsutil.resolve_path(root, "tools")
  let app = @fsutil.resolve_path(root, "Demo.app")
  let log = @fsutil.resolve_path(root, "commands.log")
  for dir in [tools, @fsutil.resolve_path(app, "Contents")] {
    ensure_dir(dir)
  }
  let xcrun = @fsutil.resolve_path(tools, "xcrun")
  let spctl = @fsutil.resolve_path(tools, "spctl")
  let script = "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"" + log + "\"\nexit 0\n"
  for path in [xcrun, spctl] {
    write_text(path, script)
    @async_fs.chmod(path, 0o755) catch {
      error => abort(@debug.render(Repr(error)))
    }
  }
  let old_profile = @env.get_env_var("PROTON_NOTARY_PROFILE")
  defer restore_package_env("PROTON_NOTARY_PROFILE", old_profile)
  @env.set_env_var("PROTON_NOTARY_PROFILE", "test-profile")
  let notary_tools = MacosNotaryTools::{ xcrun, spctl }
  let plan = PackagePlan::{
    root,
    workspace_root: root,
    build_target_dir: @fsutil.resolve_path(root, "build"),
    app_package: "app",
    config_path: @fsutil.resolve_path(root, "proton.project.json"),
    product_name: "Demo",
    identifier: "dev.proton.demo",
    version: "1.0.0",
    macos_version: "1.0.0",
    bundle_version: "1.0.0",
    update_revision: 0UL,
    targets: ["app"],
    output: root,
    build: false,
    release: false,
    base_dir: root,
    frontend_dist: None,
    entry_paths: [],
    sign_binaries: [],
    resources: [],
    icons: [],
    url_schemes: [],
    document_types: [],
    macos_icon: None,
    sign: true,
    notarize: true,
  }
  notarize_macos_app_with_tools(plan, app, notary_tools)
  let commands = @mbfs.read_file_to_string(log, encoding="utf8") catch {
    error => abort(@debug.render(Repr(error)))
  }
  let archive = @fsutil.resolve_path(root, ".demo.notary.zip")
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
  try notarize_macos_app_with_tools(plan, app, notary_tools) catch {
    MacosSigningError::ToolFailure(stage~, detail~) => {
      assert_true(stage.contains("notarytool submit"))
      assert_true(detail.contains("42"))
    }
    _ => abort("expected notarization tool failure")
  } noraise {
    _ => abort("expected notarization submission failure")
  }
  let failed_commands = @mbfs.read_file_to_string(log, encoding="utf8") catch {
    error => abort(@debug.render(Repr(error)))
  }
  assert_eq(
    failed_commands,
    "notarytool submit " + archive + " --keychain-profile test-profile --wait\n",
  )
  assert_false(@mbfs.path_exists(archive))
}

///|
async test "package executable lookup ignores the dSYM mirror" {
  let root = "target/proton-package-executable-lookup"
  remove_tree(root)
  let package_target = @fsutil.resolve_path(root, "package-target")
  let unrelated = @fsutil.resolve_path(
    root, "workspace/native/release/build/other/app.exe",
  )
  ensure_dir(@fsutil.path_parent(unrelated))
  write_text(unrelated, "wrong")
  let plan = PackagePlan::{
    root,
    workspace_root: @fsutil.resolve_path(root, "workspace"),
    build_target_dir: package_target,
    app_package: "app",
    config_path: @fsutil.resolve_path(root, "proton.project.json"),
    product_name: "Demo",
    identifier: "dev.proton.demo",
    version: "1.0.0",
    macos_version: "1.0.0",
    bundle_version: "1.0.0",
    update_revision: 0UL,
    targets: ["app"],
    output: @fsutil.resolve_path(root, "output"),
    build: false,
    release: false,
    base_dir: root,
    frontend_dist: None,
    entry_paths: [],
    sign_binaries: [],
    resources: [],
    icons: [],
    url_schemes: [],
    document_types: [],
    macos_icon: None,
    sign: false,
    notarize: false,
  }
  let expected = @fsutil.resolve_path(
    package_target, "native/debug/build/vendor/app/app.exe",
  )
  @debug.assert_eq(find_package_executable(plan), None)
  let dsym = @fsutil.resolve_path(
    package_target, "native/debug/build/vendor/app/app.exe.dSYM/Contents/Resources/DWARF/app.exe",
  )
  ensure_dir(@fsutil.path_parent(dsym))
  write_text(dsym, "debug symbols")
  @debug.assert_eq(find_package_executable(plan), None)
  ensure_dir(@fsutil.path_parent(expected))
  write_text(expected, "right")
  guard find_package_executable(plan) is Some(actual) else {
    fail("expected debug executable")
  }
  assert_eq(normalize_slashes(actual), normalize_slashes(expected))
}

///|
async test "active runtime rejects another platform" {
  let root = "target/proton-package-runtime-platform"
  remove_tree(root)
  ensure_dir(@fsutil.resolve_path(root, ".proton"))
  let old_dist = @env.get_env_var("PROTON_NATIVE_DIST")
  @env.unset_env_var("PROTON_NATIVE_DIST")
  defer restore_package_env("PROTON_NATIVE_DIST", old_dist)
  let expected = @cef.current_platform_id()
  let other = if expected == "win32-x64" { "darwin-arm64" } else { "win32-x64" }
  let manifest : Json = { "platform": other, "dist": "runtime" }
  write_text(
    @fsutil.resolve_path(root, ".proton/runtime.json"),
    manifest.stringify(),
  )
  try read_active_runtime(@fsutil.resolve_path(root, ".")) catch {
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
  let output = @fsutil.resolve_path(root, "output")
  remove_tree(root)
  let runtime = prepare_windows_test_runtime(root)
  let executable = @fsutil.resolve_path(root, "demo.exe")
  let config = @fsutil.resolve_path(root, "proton.project.json")
  for item in [(executable, "exe"), (config, "config")] {
    let (path, text) = item
    write_windows_test_file(path, text)
  }
  let plan = PackagePlan::{
    root,
    workspace_root: root,
    build_target_dir: @fsutil.resolve_path(root, "package-build"),
    app_package: "app",
    config_path: config,
    product_name: "Demo App",
    identifier: "dev.proton.demo",
    version: "1.0.0",
    macos_version: "1.0.0",
    bundle_version: "1.0.0",
    update_revision: 0UL,
    targets: ["app"],
    output,
    build: false,
    release: false,
    base_dir: root,
    frontend_dist: None,
    entry_paths: [],
    sign_binaries: [],
    resources: [],
    icons: [],
    url_schemes: [],
    document_types: [],
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
  let portable = @fsutil.resolve_path(output, "demo-app")
  assert_true(@mbfs.path_exists(@fsutil.resolve_path(portable, "demo-app.exe")))
  assert_true(@mbfs.path_exists(@fsutil.resolve_path(portable, "proton.dll")))
  assert_true(
    @mbfs.path_exists(@fsutil.resolve_path(portable, "cef_process.exe")),
  )
  assert_true(@mbfs.path_exists(@fsutil.resolve_path(portable, "libcef.dll")))
  assert_true(
    @mbfs.path_exists(@fsutil.resolve_path(portable, "Resources/icudtl.dat")),
  )
  assert_false(
    @mbfs.path_exists(@fsutil.resolve_path(portable, "bin/proton.dll")),
  )
}

///|
test "a thin Mach-O header yields its filetype" {
  // An arm64 executable and its dSYM mirror: identical for twelve bytes, then
  // MH_EXECUTE (2) against MH_DSYM (10). Nothing cheaper tells them apart —
  // not the magic, not the size, not codesign.
  let executable = b"\xcf\xfa\xed\xfe\x0c\x00\x00\x01\x00\x00\x00\x00\x02\x00\x00\x00"
  let dsym = b"\xcf\xfa\xed\xfe\x0c\x00\x00\x01\x00\x00\x00\x00\x0a\x00\x00\x00"
  assert_eq(macho_thin_filetype(executable), Some(0x2))
  assert_eq(macho_thin_filetype(dsym), Some(0xa))
  // 32-bit thin headers agree up to `filetype`, so one offset reads both.
  let thin32 = b"\xce\xfa\xed\xfe\x0c\x00\x00\x00\x00\x00\x00\x00\x06\x00\x00\x00"
  assert_eq(macho_thin_filetype(thin32), Some(0x6))
}

///|
test "unjudgeable inputs are left alone rather than failed" {
  // The caller rejects only what it can prove wrong, so a universal binary, a
  // script, and a truncated file all read as None. A format this reader does
  // not understand must never become a packaging failure.
  let fat = b"\xca\xfe\xba\xbe\x00\x00\x00\x02\x01\x00\x00\x0c\x00\x00\x00\x00"
  assert_eq(macho_thin_filetype(fat), None)
  assert_eq(macho_thin_filetype(b"#!/bin/sh\necho hi\n"), None)
  assert_eq(macho_thin_filetype(b"\xcf\xfa\xed\xfe"), None)
}

///|
test "the rejection names the filetype it found" {
  inspect(macho_filetype_name(0x2), content="MH_EXECUTE")
  inspect(macho_filetype_name(0xa), content="MH_DSYM")
  inspect(
    PackagePlanError::NotLaunchableMachO(
      path="SeekMoon.app/Contents/MacOS/seekmoon",
      filetype=0xa,
    ).message(),
    content="staged bundle executable SeekMoon.app/Contents/MacOS/seekmoon is a Mach-O of type MH_DSYM, not MH_EXECUTE; the kernel refuses to spawn it",
  )
}
