///|
/// Resolves one fixture path by searching the current directory and its parents.
fn resolve_fixture_path(candidates : Array[String]) -> String {
  let mut prefix = ""
  let mut depth = 0
  while depth < 8 {
    for candidate in candidates {
      let resolved = prefix + candidate
      if @mbfs.path_exists(resolved) {
        return resolved
      }
    }
    prefix = prefix + "../"
    depth = depth + 1
  }
  candidates[0]
}

///|
/// Normalizes test paths so assertions stay stable across Windows and Unix separators.
fn normalize_test_slashes(path : String) -> String {
  let builder = StringBuilder::new(size_hint=path.length())
  for _, ch in path {
    builder.write_char(if ch == '\\' { '/' } else { ch })
  }
  builder.to_string()
}

///|
/// Resolves one bootstrap manifest fixture path from either module-local or workspace layout.
fn manifest_test_path(name : String) -> String {
  resolve_fixture_path([
    "testdata/" + name,
    "proton/bootstrap/testdata/" + name,
    "bootstrap/testdata/" + name,
  ])
}

///|
/// Writes a minimal moon.proton with one extra top-level field and checks the error.
fn expect_moon_proton_extra_field_error(
  extra : String,
  expected : String,
) -> Unit {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir("target/proton-extra-field") catch {
    _ => ()
  }
  let config_path = "target/proton-extra-field/moon.proton"
  @mbfs.write_string_to_file(
    config_path,
    (
      #|window = {
      #|  title: "Invalid",
      #|  width: 900,
      #|  height: 700,
      #|}
      #|
      #|entry = {
      #|  kind: "html",
      #|  value: "<html></html>",
      #|}
      #|
    ) +
    extra +
    "\n",
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  match load_config_manifest_from_file(config_path) {
    Ok(_) => abort("expected moon.proton field rejection")
    Err(error) => if error != expected { abort("unexpected error: " + error) }
  }
}

///|
test "load_config_manifest_from_file rebases file entry and bool debug" {
  let result = load_config_manifest_from_file(manifest_test_path("moon.proton"))
  match result {
    Err(error) => abort(error)
    Ok(loaded) => {
      let manifest = loaded.manifest()
      assert_eq(manifest.window.title, "Proton Runtime")
      assert_eq(manifest.window.width, 840)
      assert_eq(manifest.window.height, 600)
      assert_eq(manifest.window.size_hint, @manifest.WindowSizeHint::Fixed)
      assert_eq(manifest.debug, 1)
      match manifest.entry {
        File(path) =>
          assert_true(
            normalize_test_slashes(path).has_suffix("testdata/app.html"),
          )
        _ => abort("expected file entry")
      }
    }
  }
}

///|
test "load_config_manifest_from_file accepts explicit config filenames" {
  match load_config_manifest_from_file(manifest_test_path("moon.proton")) {
    Err(error) => abort(error)
    Ok(loaded) => assert_eq(loaded.manifest().debug, 1)
  }

  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir("target/proton-alt-config") catch {
    _ => ()
  }
  let config_path = "target/proton-alt-config/proton.dev"
  @mbfs.write_string_to_file(
    config_path,
    (
      #|window = {
      #|  title: "Alt Config",
      #|  width: 720,
      #|  height: 480,
      #|}
      #|
      #|entry = {
      #|  kind: "url",
      #|  value: "http://localhost:5173",
      #|}
      #|
      #|debug = true
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  match load_config_manifest_from_file(config_path) {
    Err(error) => abort(error)
    Ok(loaded) => {
      let manifest = loaded.manifest()
      assert_eq(manifest.window.title, "Alt Config")
      assert_eq(manifest.debug, 1)
      match manifest.entry {
        Url(url) => assert_eq(url, "http://localhost:5173")
        _ => abort("expected url entry")
      }
    }
  }
}

///|
test "load_config_manifest_from_file rejects extension settings" {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir("target/proton-unsupported") catch {
    _ => ()
  }
  let config_path = "target/proton-unsupported/moon.proton"
  @mbfs.write_string_to_file(
    config_path,
    (
      #|window = {
      #|  title: "Invalid",
      #|  width: 900,
      #|  height: 700,
      #|}
      #|
      #|entry = {
      #|  kind: "html",
      #|  value: "<html></html>",
      #|}
      #|
      #|extensions = {}
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  match load_config_manifest_from_file(config_path) {
    Ok(_) => abort("expected extensions rejection")
    Err(error) =>
      assert_eq(
        error, "moon.proton field `extensions` is not supported; declare extensions in MoonBit code with .extension(...)",
      )
  }
}

///|
test "load_config_manifest_from_file rejects unsupported top-level fields" {
  expect_moon_proton_extra_field_error(
    "version = \"1.0.0\"", "Unexpected key 'version' found in moon.proton.",
  )
  expect_moon_proton_extra_field_error(
    "license = \"MIT\"", "Unexpected key 'license' found in moon.proton.",
  )
  expect_moon_proton_extra_field_error(
    "description = \"App\"", "Unexpected key 'description' found in moon.proton.",
  )
  expect_moon_proton_extra_field_error(
    "permissions = {}", "moon.proton field `permissions` is not supported in v1",
  )
  expect_moon_proton_extra_field_error(
    "windows = []", "moon.proton field `windows` is not supported in v1",
  )
  expect_moon_proton_extra_field_error(
    "debug = 1", "moon.proton debug must be a bool",
  )
}

///|
test "load_proton_project_config_from_file decodes tooling blocks and moon.mod metadata" {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir("target/proton-project-config") catch {
    _ => ()
  }
  @mbfs.write_string_to_file(
    "target/proton-project-config/moon.mod",
    (
      #|name = "vendor/app"
      #|version = "1.2.3"
      #|license = "MIT"
      #|description = "Desktop app"
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  let config_path = "target/proton-project-config/moon.proton"
  @mbfs.write_string_to_file(
    config_path,
    (
      #|product_name = "Desktop App"
      #|identifier = "com.vendor.app"
      #|
      #|window = {
      #|  title: "Runtime Title",
      #|  width: 900,
      #|  height: 700,
      #|}
      #|
      #|entry = {
      #|  kind: "asset",
      #|  value: "frontend/dist/index.html",
      #|}
      #|
      #|debug = true
      #|
      #|frontend = {
      #|  dev_url: "http://localhost:5173",
      #|  dist: "frontend/dist",
      #|  cwd: "frontend",
      #|  before_dev: "npm run dev",
      #|  before_build: "npm run build",
      #|}
      #|
      #|bundle = {
      #|  active: true,
      #|  targets: ["app", "zip"],
      #|  icon: ["icons/icon.ico"],
      #|  resources: ["resources/**"],
      #|  output: "target/proton-dist",
      #|}
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }

  let project = match load_proton_project_config_from_file(config_path) {
    Ok(project) => project
    Err(error) => abort(error)
  }

  assert_eq(project.manifest().manifest().debug, 1)
  let metadata = project.metadata()
  assert_eq(metadata.product_name(), "Desktop App")
  @debug.assert_eq(metadata.identifier(), Some("com.vendor.app"))
  @debug.assert_eq(metadata.version(), Some("1.2.3"))
  @debug.assert_eq(metadata.description(), Some("Desktop app"))
  @debug.assert_eq(metadata.license(), Some("MIT"))

  match project.frontend() {
    None => abort("expected frontend config")
    Some(frontend) => {
      @debug.assert_eq(frontend.dev_url(), Some("http://localhost:5173"))
      assert_true(
        normalize_test_slashes(frontend.dist().unwrap()).has_suffix(
          "target/proton-project-config/frontend/dist",
        ),
      )
      assert_true(
        normalize_test_slashes(frontend.cwd().unwrap()).has_suffix(
          "target/proton-project-config/frontend",
        ),
      )
      @debug.assert_eq(frontend.before_dev(), Some("npm run dev"))
      @debug.assert_eq(frontend.before_build(), Some("npm run build"))
    }
  }

  match project.bundle() {
    None => abort("expected bundle config")
    Some(bundle) => {
      assert_true(bundle.active())
      @debug.assert_eq(bundle.targets(), ["app", "zip"])
      assert_true(
        normalize_test_slashes(bundle.icon()[0]).has_suffix(
          "target/proton-project-config/icons/icon.ico",
        ),
      )
      assert_true(
        normalize_test_slashes(bundle.resources()[0]).has_suffix(
          "target/proton-project-config/resources/**",
        ),
      )
      assert_true(
        normalize_test_slashes(bundle.output()).has_suffix(
          "target/proton-project-config/target/proton-dist",
        ),
      )

      let targets = bundle.targets()
      targets.push("mutated")
      @debug.assert_eq(bundle.targets(), ["app", "zip"])
    }
  }

  let dev_loaded = project.dev_manifest()
  @debug.assert_eq(dev_loaded.base_dir(), project.manifest().base_dir())
  match dev_loaded.manifest().entry {
    Url(url) => assert_eq(url, "http://localhost:5173")
    _ => abort("expected dev manifest to use frontend.dev_url")
  }

  match project.to_summary_json() {
    Object(summary) => {
      match summary.get("runtime") {
        Some(Object(runtime)) => {
          @debug.assert_eq(runtime.get("debug"), Some(Json::boolean(true)))
          match runtime.get("entry") {
            Some(Object(entry)) => {
              @debug.assert_eq(entry.get("kind"), Some(Json::string("asset")))
              match entry.get("value") {
                Some(String(path)) =>
                  assert_true(
                    normalize_test_slashes(path).has_suffix(
                      "target/proton-project-config/frontend/dist/index.html",
                    ),
                  )
                _ => abort("expected runtime.entry value")
              }
            }
            _ => abort("expected runtime.entry summary")
          }
          match runtime.get("dev_entry") {
            Some(Object(entry)) => {
              @debug.assert_eq(entry.get("kind"), Some(Json::string("url")))
              @debug.assert_eq(
                entry.get("value"),
                Some(Json::string("http://localhost:5173")),
              )
            }
            _ => abort("expected runtime.dev_entry summary")
          }
        }
        _ => abort("expected runtime summary")
      }
      match summary.get("metadata") {
        Some(Object(metadata)) => {
          @debug.assert_eq(
            metadata.get("product_name"),
            Some(Json::string("Desktop App")),
          )
          @debug.assert_eq(metadata.get("version"), Some(Json::string("1.2.3")))
        }
        _ => abort("expected metadata summary")
      }
      match summary.get("bundle") {
        Some(Object(bundle)) => {
          @debug.assert_eq(bundle.get("active"), Some(Json::boolean(true)))
          match bundle.get("output") {
            Some(String(output)) =>
              assert_true(
                normalize_test_slashes(output).has_suffix(
                  "target/proton-project-config/target/proton-dist",
                ),
              )
            _ => abort("expected bundle output summary")
          }
        }
        _ => abort("expected bundle summary")
      }
    }
    _ => abort("expected object summary")
  }

  let loaded_summary = match
    load_proton_project_summary_from_file(config_path) {
    Ok(summary) => summary
    Err(error) => abort(error)
  }
  @debug.assert_eq(loaded_summary, project.to_summary_json())
}

///|
test "proton project dev_manifest keeps entry when dev_url is absent" {
  let loaded = LoadedAppManifest::new(
    @manifest.AppManifest::new(
      @manifest.WindowManifest::new("App", 800, 600),
      @manifest.AppEntry::Asset("frontend/dist/index.html"),
      debug=1,
    ),
    base_dir=Some("workspace/app"),
  )
  let project = ProtonProjectConfig::new(
    loaded,
    ProtonAppMetadata::new("App"),
    frontend=Some(ProtonFrontendConfig::new(dist=Some("frontend/dist"))),
  )

  let dev_loaded = project.dev_manifest()
  @debug.assert_eq(dev_loaded.base_dir(), Some("workspace/app"))
  match dev_loaded.manifest().entry {
    Asset(path) => assert_eq(path, "frontend/dist/index.html")
    _ => abort("expected original entry without frontend.dev_url")
  }
  assert_eq(dev_loaded.manifest().debug, 1)
}

///|
test "load_proton_project_config_from_file validates tooling blocks" {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir("target/proton-project-invalid") catch {
    _ => ()
  }
  let config_path = "target/proton-project-invalid/moon.proton"
  @mbfs.write_string_to_file(
    config_path,
    (
      #|window = {
      #|  title: "Invalid",
      #|  width: 900,
      #|  height: 700,
      #|}
      #|
      #|entry = {
      #|  kind: "html",
      #|  value: "<html></html>",
      #|}
      #|
      #|frontend = {
      #|  unknown: "value",
      #|}
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }

  match load_proton_project_config_from_file(config_path) {
    Ok(_) => abort("expected frontend validation error")
    Err(error) =>
      assert_eq(
        error, "Unexpected key 'unknown' found in moon.proton field `frontend`.",
      )
  }
}

///|
test "load_config_manifest_from_file validates project tooling blocks" {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir("target/proton-config-manifest-invalid") catch {
    _ => ()
  }
  let config_path = "target/proton-config-manifest-invalid/moon.proton"
  @mbfs.write_string_to_file(
    config_path,
    (
      #|window = {
      #|  title: "Invalid",
      #|  width: 900,
      #|  height: 700,
      #|}
      #|
      #|entry = {
      #|  kind: "html",
      #|  value: "<html></html>",
      #|}
      #|
      #|frontend = {
      #|  before_buid: "npm run build",
      #|}
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }

  match load_config_manifest_from_file(config_path) {
    Ok(_) => abort("expected frontend validation error")
    Err(error) =>
      assert_eq(
        error, "Unexpected key 'before_buid' found in moon.proton field `frontend`.",
      )
  }
}

///|
test "load_proton_project_config_from_file preserves active bundle without release metadata" {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir("target/proton-project-bundle-metadata") catch {
    _ => ()
  }
  @mbfs.write_string_to_file(
    "target/proton-project-bundle-metadata/moon.mod",
    (
      #|name = "vendor/app"
      #|version = "1.0.0"
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }

  let missing_identifier = "target/proton-project-bundle-metadata/missing-identifier.moon.proton"
  @mbfs.write_string_to_file(
    missing_identifier,
    (
      #|window = {
      #|  title: "Bundle App",
      #|  width: 900,
      #|  height: 700,
      #|}
      #|
      #|entry = {
      #|  kind: "html",
      #|  value: "<html></html>",
      #|}
      #|
      #|bundle = {
      #|  active: true,
      #|}
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  match load_proton_project_config_from_file(missing_identifier) {
    Ok(config) =>
      match config.bundle() {
        Some(bundle) => assert_true(bundle.active())
        None => abort("expected active bundle")
      }
    Err(error) => abort(error)
  }
}

///|
test "load_proton_project_config_from_file validates bundle targets" {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir("target/proton-project-bundle-targets") catch {
    _ => ()
  }
  let unsupported_target = "target/proton-project-bundle-targets/unsupported.moon.proton"
  @mbfs.write_string_to_file(
    unsupported_target,
    (
      #|window = {
      #|  title: "Bundle App",
      #|  width: 900,
      #|  height: 700,
      #|}
      #|
      #|entry = {
      #|  kind: "html",
      #|  value: "<html></html>",
      #|}
      #|
      #|bundle = {
      #|  targets: ["dmg"],
      #|}
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  match load_proton_project_config_from_file(unsupported_target) {
    Ok(_) => abort("expected unsupported bundle target error")
    Err(error) =>
      assert_eq(error, "bundle.targets contains unsupported target: dmg")
  }

  let duplicate_target = "target/proton-project-bundle-targets/duplicate.moon.proton"
  @mbfs.write_string_to_file(
    duplicate_target,
    (
      #|window = {
      #|  title: "Bundle App",
      #|  width: 900,
      #|  height: 700,
      #|}
      #|
      #|entry = {
      #|  kind: "html",
      #|  value: "<html></html>",
      #|}
      #|
      #|bundle = {
      #|  targets: ["app", "app"],
      #|}
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  match load_proton_project_config_from_file(duplicate_target) {
    Ok(_) => abort("expected duplicate bundle target error")
    Err(error) =>
      assert_eq(error, "bundle.targets contains duplicate target: app")
  }
}

///|
test "app_manifest_to_json roundtrips internal runtime manifest" {
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new(
      "Roundtrip",
      900,
      640,
      size_hint=@manifest.WindowSizeHint::Min,
      titlebar_style=@manifest.TitlebarStyle::Overlay,
    ),
    @manifest.AppEntry::Asset("frontend/index.html"),
    debug=1,
    windows=[
      @manifest.AppWindowManifest::new(
        "settings",
        @manifest.WindowManifest::new(
          "Settings",
          420,
          320,
          size_hint=@manifest.WindowSizeHint::Fixed,
        ),
        @manifest.AppEntry::Html("<html>Settings</html>"),
      ),
    ],
    extensions={
      "justjavac/proton-fs": @manifest.ExtensionSetting::enabled(
        options=Some(Json::object({ "scope": Json::string("read") })),
      ),
      "justjavac/proton-tray": @manifest.ExtensionSetting::disabled(),
    },
  )
  let text = app_manifest_to_json(manifest).stringify(indent=2)
  let loaded = match load_runtime_manifest_from_json(text) {
    Ok(loaded) => loaded
    Err(error) => abort(error)
  }
  let roundtripped = loaded.manifest()
  assert_eq(roundtripped.window.title, "Roundtrip")
  assert_eq(roundtripped.window.size_hint, @manifest.WindowSizeHint::Min)
  assert_eq(
    roundtripped.window.titlebar_style,
    @manifest.TitlebarStyle::Overlay,
  )
  match roundtripped.entry {
    Asset(path) => assert_eq(path, "frontend/index.html")
    _ => abort("expected asset entry")
  }
  assert_eq(roundtripped.windows.length(), 1)
  assert_eq(
    roundtripped.windows[0].window.size_hint,
    @manifest.WindowSizeHint::Fixed,
  )
  @debug.assert_eq(
    roundtripped.extension_setting("justjavac/proton-fs"),
    Some(
      @manifest.ExtensionSetting::enabled(
        options=Some(Json::object({ "scope": Json::string("read") })),
      ),
    ),
  )
  @debug.assert_eq(
    roundtripped.extension_setting("justjavac/proton-tray"),
    Some(@manifest.ExtensionSetting::disabled()),
  )
}
