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
fn[T] expect_bootstrap_error(
  action : () -> T raise BootstrapError,
) -> BootstrapError {
  try {
    let _ = action()
    abort("expected bootstrap error")
  } catch {
    error => error
  }
}

///|
/// Writes a minimal proton.project.json with one extra top-level field and checks the error.
fn expect_project_extra_field_error(
  key : String,
  value : Json,
  expected : String,
) -> Unit {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir("target/proton-extra-field") catch {
    _ => ()
  }
  let config_path = "target/proton-extra-field/proton.project.json"
  let config : Json = {
    "window": { "title": "Invalid", "width": 900, "height": 700 },
    "entry": { "kind": "html", "value": "<html></html>" },
  }
  guard config is Object(fields) else {
    abort("expected project config object")
  }
  fields[key] = value
  @mbfs.write_string_to_file(
    config_path,
    Json::object(fields).stringify(indent=2) + "\n",
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  let error = expect_bootstrap_error(() => {
    load_config_manifest_from_file(config_path)
  })
  if error.message() != expected {
    abort("unexpected error: " + error.message())
  }
}

///|
test "load_config_manifest_from_file rebases file entry and bool debug" {
  let loaded = load_config_manifest_from_file(
    manifest_test_path("proton.project.json"),
  )
  let manifest = loaded.manifest()
  assert_eq(manifest.window.title, "Proton Runtime")
  assert_eq(manifest.window.width, 840)
  assert_eq(manifest.window.height, 600)
  assert_eq(manifest.window.size_hint, @manifest.WindowSizeHint::Fixed)
  assert_eq(manifest.debug, 1)
  match manifest.entry {
    File(path) =>
      assert_true(normalize_test_slashes(path).has_suffix("testdata/app.html"))
    _ => abort("expected file entry")
  }
}

///|
test "load_config_manifest_from_file accepts explicit config filenames" {
  let loaded = load_config_manifest_from_file(
    manifest_test_path("proton.project.json"),
  )
  assert_eq(loaded.manifest().debug, 1)

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
      #|{
      #|  "window": {
      #|    "title": "Alt Config",
      #|    "width": 720,
      #|    "height": 480
      #|  },
      #|  "entry": {
      #|    "kind": "url",
      #|    "value": "http://localhost:5173"
      #|  },
      #|  "debug": true
      #|}
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  let loaded = load_config_manifest_from_file(config_path)
  let manifest = loaded.manifest()
  assert_eq(manifest.window.title, "Alt Config")
  assert_eq(manifest.debug, 1)
  match manifest.entry {
    Url(url) => assert_eq(url, "http://localhost:5173")
    _ => abort("expected url entry")
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
  let config_path = "target/proton-unsupported/proton.project.json"
  @mbfs.write_string_to_file(
    config_path,
    (
      #|{
      #|  "window": {
      #|    "title": "Invalid",
      #|    "width": 900,
      #|    "height": 700
      #|  },
      #|  "entry": {
      #|    "kind": "html",
      #|    "value": "<html></html>"
      #|  },
      #|  "extensions": {}
      #|}
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  let error = expect_bootstrap_error(() => {
    load_config_manifest_from_file(config_path)
  })
  assert_eq(
    error.message(),
    "proton.project.json field `extensions` is not supported; declare extensions in MoonBit code with .extension(...).",
  )
}

///|
test "load_config_manifest_from_file rejects unsupported top-level fields" {
  expect_project_extra_field_error(
    "version", "1.0.0", "Unexpected key 'version' found in proton.project.json.",
  )
  expect_project_extra_field_error(
    "license", "MIT", "Unexpected key 'license' found in proton.project.json.",
  )
  expect_project_extra_field_error(
    "description", "App", "Unexpected key 'description' found in proton.project.json.",
  )
  expect_project_extra_field_error(
    "permissions",
    {},
    "proton.project.json.permissions must be an array",
  )
  expect_project_extra_field_error(
    "debug", 1, "proton.project.json.debug must be a bool",
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
  @mbfs.create_dir("target/proton-project-config/backend") catch {
    _ => ()
  }
  @mbfs.write_string_to_file(
    "target/proton-project-config/backend/moon.mod",
    (
      #|name = "vendor/app"
      #|version = "1.2.3"
      #|license = "MIT"
      #|description = "Desktop app"
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  let config_path = "target/proton-project-config/proton.project.json"
  @mbfs.write_string_to_file(
    config_path,
    (
      #|{
      #|  "product_name": "Desktop App",
      #|  "identifier": "com.vendor.app",
      #|  "window": {
      #|    "title": "Runtime Title",
      #|    "width": 900,
      #|    "height": 700
      #|  },
      #|  "entry": {
      #|    "kind": "asset",
      #|    "value": "frontend/dist/index.html"
      #|  },
      #|  "windows": [
      #|    {
      #|      "id": "settings",
      #|      "window": {
      #|        "title": "Settings",
      #|        "width": 480,
      #|        "height": 360
      #|      },
      #|      "entry": {
      #|        "kind": "html",
      #|        "value": "<main>Settings</main>"
      #|      }
      #|    }
      #|  ],
      #|  "debug": true,
      #|  "backend": {
      #|    "path": "backend",
      #|    "package": "app"
      #|  },
      #|  "frontend": {
      #|    "dev_url": "http://localhost:5173",
      #|    "dist": "dist",
      #|    "path": "frontend",
      #|    "before_dev": "npm run dev",
      #|    "before_build": "npm run build"
      #|  },
      #|  "bundle": {
      #|    "active": true,
      #|    "targets": [
      #|      "app",
      #|      "zip"
      #|    ],
      #|    "icon": [
      #|      "icons/icon.ico"
      #|    ],
      #|    "resources": [
      #|      "resources/**"
      #|    ],
      #|    "sign": {
      #|      "binaries": [
      #|        "bin/worker"
      #|      ]
      #|    },
      #|    "url_schemes": [
      #|      "desktop-app"
      #|    ],
      #|    "document_types": [
      #|      {
      #|        "name": "Desktop document",
      #|        "extensions": [
      #|          "desktop"
      #|        ],
      #|        "role": "Editor"
      #|      }
      #|    ],
      #|    "output": "target/proton-dist"
      #|  }
      #|}
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }

  let project = load_proton_project_config_from_file(config_path)

  assert_eq(project.manifest().manifest().debug, 1)
  let metadata = project.metadata()
  assert_eq(metadata.product_name(), "Desktop App")
  @debug.assert_eq(metadata.identifier(), Some("com.vendor.app"))
  @debug.assert_eq(metadata.version(), Some("1.2.3"))
  @debug.assert_eq(metadata.description(), Some("Desktop app"))
  @debug.assert_eq(metadata.license(), Some("MIT"))

  match project.backend() {
    None => abort("expected backend config")
    Some(backend) => {
      assert_true(
        normalize_test_slashes(backend.path()).has_suffix(
          "target/proton-project-config/backend",
        ),
      )
      assert_eq(backend.app_package(), "app")
    }
  }

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
        normalize_test_slashes(frontend.path().unwrap()).has_suffix(
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
      match bundle.sign() {
        Some(sign) =>
          assert_true(
            normalize_test_slashes(sign.binaries()[0]).has_suffix(
              "target/proton-project-config/bin/worker",
            ),
          )
        None => fail("expected bundle sign config")
      }
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

  guard project.to_summary_json()
    is {
      "runtime": {
        "debug": true,
        "entry": { "kind": "asset", "value": String(entry_path), .. },
        "dev_entry": { "kind": "url", "value": "http://localhost:5173", .. },
        "windows": [{ "id": "settings", .. }],
        ..
      },
      "metadata": { "product_name": "Desktop App", "version": "1.2.3", .. },
      "bundle": {
        "active": true,
        "url_schemes": ["desktop-app"],
        "sign": { "binaries": [String(binary_path)], .. },
        "document_types": [{ "name": "Desktop document", "role": "Editor", .. }],
        "output": String(output),
        ..
      },
      ..
    } else {
    abort("unexpected project summary JSON")
  }
  assert_true(
    normalize_test_slashes(entry_path).has_suffix(
      "target/proton-project-config/frontend/dist/index.html",
    ),
  )
  assert_true(
    normalize_test_slashes(binary_path).has_suffix(
      "target/proton-project-config/bin/worker",
    ),
  )
  assert_true(
    normalize_test_slashes(output).has_suffix(
      "target/proton-project-config/target/proton-dist",
    ),
  )

  let loaded_summary = load_proton_project_summary_from_file(config_path)
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
  let config_path = "target/proton-project-invalid/proton.project.json"
  @mbfs.write_string_to_file(
    config_path,
    (
      #|{
      #|  "window": {
      #|    "title": "Invalid",
      #|    "width": 900,
      #|    "height": 700
      #|  },
      #|  "entry": {
      #|    "kind": "html",
      #|    "value": "<html></html>"
      #|  },
      #|  "frontend": {
      #|    "unknown": "value"
      #|  }
      #|}
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }

  let error = expect_bootstrap_error(() => {
    load_proton_project_config_from_file(config_path)
  })
  assert_eq(
    error.message(),
    "Unexpected key 'unknown' found in proton.project.json field `frontend`.",
  )
}

///|
test "load_config_manifest_from_file validates project tooling blocks" {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir("target/proton-config-manifest-invalid") catch {
    _ => ()
  }
  let config_path = "target/proton-config-manifest-invalid/proton.project.json"
  @mbfs.write_string_to_file(
    config_path,
    (
      #|{
      #|  "window": {
      #|    "title": "Invalid",
      #|    "width": 900,
      #|    "height": 700
      #|  },
      #|  "entry": {
      #|    "kind": "html",
      #|    "value": "<html></html>"
      #|  },
      #|  "frontend": {
      #|    "before_buid": "npm run build"
      #|  }
      #|}
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }

  let error = expect_bootstrap_error(() => {
    load_config_manifest_from_file(config_path)
  })
  assert_eq(
    error.message(),
    "Unexpected key 'before_buid' found in proton.project.json field `frontend`.",
  )
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
    err => abort(@debug.render(Repr(err)))
  }

  let missing_identifier = "target/proton-project-bundle-metadata/missing-identifier.proton.project.json"
  @mbfs.write_string_to_file(
    missing_identifier,
    (
      #|{
      #|  "window": {
      #|    "title": "Bundle App",
      #|    "width": 900,
      #|    "height": 700
      #|  },
      #|  "entry": {
      #|    "kind": "html",
      #|    "value": "<html></html>"
      #|  },
      #|  "bundle": {
      #|    "active": true
      #|  }
      #|}
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  let config = load_proton_project_config_from_file(missing_identifier)
  match config.bundle() {
    Some(bundle) => assert_true(bundle.active())
    None => abort("expected active bundle")
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
  let supported_target = "target/proton-project-bundle-targets/supported.proton.project.json"
  @mbfs.write_string_to_file(
    supported_target,
    (
      #|{
      #|  "window": {
      #|    "title": "Bundle App",
      #|    "width": 900,
      #|    "height": 700
      #|  },
      #|  "entry": {
      #|    "kind": "html",
      #|    "value": "<html></html>"
      #|  },
      #|  "bundle": {
      #|    "targets": [
      #|      "app",
      #|      "zip",
      #|      "dmg"
      #|    ]
      #|  }
      #|}
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  let supported = load_proton_project_config_from_file(supported_target)
  assert_eq(supported.bundle().unwrap().targets(), ["app", "zip", "dmg"])

  let unsupported_target = "target/proton-project-bundle-targets/unsupported.proton.project.json"
  @mbfs.write_string_to_file(
    unsupported_target,
    (
      #|{
      #|  "window": {
      #|    "title": "Bundle App",
      #|    "width": 900,
      #|    "height": 700
      #|  },
      #|  "entry": {
      #|    "kind": "html",
      #|    "value": "<html></html>"
      #|  },
      #|  "bundle": {
      #|    "targets": [
      #|      "msi"
      #|    ]
      #|  }
      #|}
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  let error = expect_bootstrap_error(() => {
    load_proton_project_config_from_file(unsupported_target)
  })
  assert_eq(error.message(), "unsupported bundle.targets: msi")

  let duplicate_target = "target/proton-project-bundle-targets/duplicate.proton.project.json"
  @mbfs.write_string_to_file(
    duplicate_target,
    (
      #|{
      #|  "window": {
      #|    "title": "Bundle App",
      #|    "width": 900,
      #|    "height": 700
      #|  },
      #|  "entry": {
      #|    "kind": "html",
      #|    "value": "<html></html>"
      #|  },
      #|  "bundle": {
      #|    "targets": [
      #|      "app",
      #|      "app"
      #|    ]
      #|  }
      #|}
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  let error = expect_bootstrap_error(() => {
    load_proton_project_config_from_file(duplicate_target)
  })
  assert_eq(error.message(), "duplicate value in bundle.targets: app")
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
      "moonbit-community/proton-fs": @manifest.ExtensionSetting::enabled(),
      "moonbit-community/proton-tray": @manifest.ExtensionSetting::disabled(),
    },
    permissions=[
      @manifest.PermissionGrant::new(
        "main",
        @manifest.PermissionOrigin::App,
        "moonbit-community/proton-fs",
        scope=Json::object({ "read": Json::array([Json::string("./data")]) }),
      ),
    ],
  )
  let text = app_manifest_to_json(manifest).stringify(indent=2)
  let loaded = load_runtime_manifest_from_json(text)
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
    roundtripped.extension_setting("moonbit-community/proton-fs"),
    Some(@manifest.ExtensionSetting::enabled()),
  )
  @debug.assert_eq(
    roundtripped.extension_setting("moonbit-community/proton-tray"),
    Some(@manifest.ExtensionSetting::disabled()),
  )
  let grants = roundtripped.permission_grants()
  assert_eq(grants.length(), 1)
  assert_eq(grants[0].window(), "main")
  assert_eq(grants[0].origin(), @manifest.PermissionOrigin::App)
  assert_eq(grants[0].extension(), "moonbit-community/proton-fs")
}
