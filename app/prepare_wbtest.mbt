///|
/// Builds a minimal extension spec for app preparation tests.
fn stub_extension(
  id : String,
  js_namespace? : String? = None,
  dependencies? : Array[String] = [],
) -> @core.ExtensionSpec {
  let extension_namespace = match js_namespace {
    Some(value) => value
    None => id
  }
  @core.ExtensionSpec::new(
    id,
    extension_namespace,
    fn(_context) {
      Ok(@core.Extension::new(id, extension_namespace, fn(_context) {  }))
    },
    dependencies~,
  )
}

///|
/// Builds a representative manifest fixture for app preparation tests.
fn demo_manifest(
  extensions : Map[String, @manifest.ExtensionSetting],
) -> @manifest.AppManifest {
  @manifest.AppManifest::new(
    @manifest.WindowManifest::new("Planner", 960, 720),
    @manifest.AppEntry::Html("<html></html>"),
    debug=2,
    windows=[
      @manifest.AppWindowManifest::new(
        "settings",
        @manifest.WindowManifest::new("Settings", 420, 320),
        @manifest.AppEntry::File("settings.html"),
      ),
    ],
    extensions~,
  )
}

///|
/// Collects prepared extension ids in registration order for assertions.
fn prepared_extension_ids(prepared : PreparedApp) -> Array[String] {
  let ids : Array[String] = []
  for extension in prepared.prepared_extensions() {
    ids.push(extension.id())
  }
  ids
}

///|
test "prepare_app expands dependencies in deterministic order" {
  let registry = ExtensionRegistry::new()
    .register(stub_extension("justjavac/lepus-path", js_namespace=Some("path")))
    .register(
      stub_extension("justjavac/lepus-fs", js_namespace=Some("fs"), dependencies=[
        "justjavac/lepus-path",
      ]),
    )
    .register(
      stub_extension("justjavac/lepus-dialog", js_namespace=Some("dialog")),
    )

  let manifest = demo_manifest({
    "justjavac/lepus-fs": @manifest.ExtensionSetting::enabled(
      options=Some(Json::object({ "scope": Json::string("read") })),
    ),
    "justjavac/lepus-dialog": @manifest.ExtensionSetting::enabled(),
  })

  match prepare_app(manifest, registry, base_dir=Some("D:/workspace/app")) {
    Err(error) => abort(error)
    Ok(prepared) => {
      @debug.assert_eq(prepared_extension_ids(prepared), [
        "justjavac/lepus-path", "justjavac/lepus-fs", "justjavac/lepus-dialog",
      ])
      @debug.assert_eq(prepared.base_dir(), Some("D:/workspace/app"))
      let runtime_config = prepared.runtime_config()
      assert_eq(runtime_config.window.title, "Planner")
      assert_eq(runtime_config.window.width, 960)
      assert_eq(runtime_config.window.height, 720)
      assert_eq(runtime_config.debug, 2)
      assert_eq(runtime_config.windows.length(), 1)
      match runtime_config.entry {
        @wvrt.AppEntry::Html(html) => assert_eq(html, "<html></html>")
        _ => abort("expected html runtime entry")
      }
      match runtime_config.windows[0].entry {
        @wvrt.AppEntry::File(path) => assert_eq(path, "settings.html")
        _ => abort("expected file entry")
      }
    }
  }
}

///|
test "prepare_app preserves asset-backed runtime entries" {
  let registry = ExtensionRegistry::new()
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new("Asset Planner", 960, 720),
    @manifest.AppEntry::Asset("frontend/index.html"),
  )

  match prepare_app(manifest, registry, base_dir=Some("D:/workspace/app")) {
    Err(error) => abort(error)
    Ok(prepared) =>
      match prepared.runtime_config().entry {
        @wvrt.AppEntry::Asset(path) => assert_eq(path, "frontend/index.html")
        _ => abort("expected asset runtime entry")
      }
  }
}

///|
test "prepare_app rejects unknown manifest extension keys" {
  let registry = ExtensionRegistry::new()
  let manifest = demo_manifest({
    "justjavac/lepus-fs": @manifest.ExtensionSetting::enabled(),
  })
  match prepare_app(manifest, registry) {
    Err(error) => assert_eq(error, "unknown extension key: justjavac/lepus-fs")
    Ok(_) => abort("expected unknown extension error")
  }
}

///|
test "prepare_app rejects disabled dependencies" {
  let registry = ExtensionRegistry::new()
    .register(stub_extension("justjavac/lepus-path", js_namespace=Some("path")))
    .register(
      stub_extension("justjavac/lepus-fs", js_namespace=Some("fs"), dependencies=[
        "justjavac/lepus-path",
      ]),
    )

  let manifest = demo_manifest({
    "justjavac/lepus-path": @manifest.ExtensionSetting::disabled(),
    "justjavac/lepus-fs": @manifest.ExtensionSetting::enabled(),
  })

  match prepare_app(manifest, registry) {
    Err(error) =>
      assert_eq(
        error, "extension justjavac/lepus-fs requires disabled dependency justjavac/lepus-path",
      )
    Ok(_) => abort("expected disabled dependency error")
  }
}

///|
test "prepare_app rejects dependency cycles" {
  let registry = ExtensionRegistry::new()
    .register(
      stub_extension("vendor/alpha", js_namespace=Some("alpha"), dependencies=[
        "vendor/beta",
      ]),
    )
    .register(
      stub_extension("vendor/beta", js_namespace=Some("beta"), dependencies=[
        "vendor/alpha",
      ]),
    )

  let manifest = demo_manifest({
    "vendor/alpha": @manifest.ExtensionSetting::enabled(),
  })

  match prepare_app(manifest, registry) {
    Err(error) =>
      assert_eq(error, "extension dependency cycle detected at: vendor/alpha")
    Ok(_) => abort("expected dependency cycle error")
  }
}

///|
test "prepare_app rejects reserved secondary window ids" {
  let registry = ExtensionRegistry::new()
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new("Planner", 960, 720),
    @manifest.AppEntry::Html("<html></html>"),
    windows=[
      @manifest.AppWindowManifest::new(
        "main",
        @manifest.WindowManifest::new("Settings", 420, 320),
        @manifest.AppEntry::File("settings.html"),
      ),
    ],
  )
  match prepare_app(manifest, registry) {
    Err(error) =>
      assert_eq(error, "window id \"main\" is reserved for the primary window")
    Ok(_) => abort("expected reserved window id error")
  }
}

///|
test "prepare_app rejects duplicate secondary window ids" {
  let registry = ExtensionRegistry::new()
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new("Planner", 960, 720),
    @manifest.AppEntry::Html("<html></html>"),
    windows=[
      @manifest.AppWindowManifest::new(
        "settings",
        @manifest.WindowManifest::new("Settings", 420, 320),
        @manifest.AppEntry::File("settings.html"),
      ),
      @manifest.AppWindowManifest::new(
        "settings",
        @manifest.WindowManifest::new("Settings Again", 420, 320),
        @manifest.AppEntry::File("settings-again.html"),
      ),
    ],
  )
  match prepare_app(manifest, registry) {
    Err(error) => assert_eq(error, "duplicate window id: settings")
    Ok(_) => abort("expected duplicate window id error")
  }
}

///|
test "mbt backend config preserves process fields" {
  let descriptor = @core.IpcExtensionDescriptor::new("vendor/demo", "demo", [
    @core.IpcExtensionApi::new("ping"),
  ])
  let backend = MbtProcessBackendConfig::new(
    "backend.exe",
    ["app:ping"],
    args=["--dev"],
    cwd=Some("D:/workspace/app"),
    extensions=[descriptor],
  )
  assert_eq(backend.command(), "backend.exe")
  @debug.assert_eq(backend.op_names(), ["app:ping"])
  @debug.assert_eq(backend.args(), ["--dev"])
  @debug.assert_eq(backend.cwd(), Some("D:/workspace/app"))
  assert_eq(backend.extensions().length(), 1)
}

///|
test "mbt backend config rejects empty command" {
  let backend = MbtProcessBackendConfig::new("", ["app:ping"])
  match validate_mbt_process_backend_config(backend) {
    Err(error) =>
      assert_eq(error, "MBT process backend command must not be empty")
    Ok(_) => abort("expected empty command error")
  }
}

///|
test "mbt backend config rejects missing ops" {
  let backend = MbtProcessBackendConfig::new("backend.exe", [])
  match validate_mbt_process_backend_config(backend) {
    Err(error) =>
      assert_eq(error, "MBT process backend must expose at least one op")
    Ok(_) => abort("expected missing op error")
  }
}

///|
test "mbt backend config rejects empty op names" {
  let backend = MbtProcessBackendConfig::new("backend.exe", ["app:ping", ""])
  match validate_mbt_process_backend_config(backend) {
    Err(error) =>
      assert_eq(error, "MBT process backend op name must not be empty")
    Ok(_) => abort("expected empty op name error")
  }
}
