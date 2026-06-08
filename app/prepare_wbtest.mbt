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
fn stub_command_extension(
  id : String,
  js_namespace? : String? = None,
  dependencies? : Array[String] = [],
) -> AppCommandExtensionSpec {
  let extension_namespace = match js_namespace {
    Some(value) => value
    None => id
  }
  AppCommandExtensionSpec::new(
    id,
    extension_namespace,
    [AppCommandApiDescriptor::new("ping")],
    fn(_context) { Ok(()) },
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
test "framework manifest keeps framework extensions and strips command extensions" {
  let framework_registry = ExtensionRegistry::new().register(
    stub_extension("justjavac/lepus-path", js_namespace=Some("path")),
  )
  let command_registry = AppCommandExtensionRegistry::new().register(
    stub_command_extension("examples/async-add", js_namespace=Some("add")),
  )
  let manifest = demo_manifest({
    "justjavac/lepus-path": @manifest.ExtensionSetting::enabled(),
    "examples/async-add": @manifest.ExtensionSetting::enabled(),
  })
  let prepared = match
    plan_app_command_extensions(
      manifest,
      command_registry,
      extension_registry=framework_registry,
    ) {
    Ok(prepared) => prepared
    Err(error) => abort(error)
  }
  assert_eq(prepared.length(), 1)
  let commands = app_commands_config_from_prepared(
    prepared,
    framework_registry.spec_map(),
  )
  match
    validate_framework_manifest_extensions(
      manifest, framework_registry, commands,
    ) {
    Err(error) => abort(error)
    Ok(_) => ()
  }
  let framework_manifest = framework_manifest_for_commands(
    manifest, framework_registry, commands,
  )
  @debug.assert_eq(
    framework_manifest.extension_setting("justjavac/lepus-path"),
    Some(@manifest.ExtensionSetting::enabled()),
  )
  @debug.assert_eq(
    framework_manifest.extension_setting("examples/async-add"),
    None,
  )
}

///|
test "command extension planning rejects keys outside both registries" {
  let command_registry = AppCommandExtensionRegistry::new().register(
    stub_command_extension("examples/async-add", js_namespace=Some("add")),
  )
  let manifest = demo_manifest({
    "examples/typo": @manifest.ExtensionSetting::enabled(),
  })
  match plan_app_command_extensions(manifest, command_registry) {
    Err(error) =>
      assert_eq(
        error, "unknown framework or command extension key: examples/typo",
      )
    Ok(_) => abort("expected unknown command extension error")
  }
}

///|
test "framework config writer validates linked framework dependencies" {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  let path = "target/framework-dependency-wbtest.json"
  let manifest = demo_manifest({})
  let commands = AppCommandsConfig::new(["app:ping"], framework_extension_ids=[
    "justjavac/lepus-path",
  ])
  let ipc_config = match
    make_framework_ipc_launch_config(Some("dependency-token")) {
    Err(error) => abort(error)
    Ok(config) => config
  }
  match
    write_framework_process_ipc_config(path, manifest, ipc_config, commands) {
    Err(error) =>
      assert_eq(
        error, "unknown command framework dependency: justjavac/lepus-path",
      )
    Ok(_) => abort("expected missing framework dependency error")
  }
  let framework_registry = ExtensionRegistry::new().register(
    stub_extension("justjavac/lepus-path", js_namespace=Some("path")),
  )
  match
    write_framework_process_ipc_config(
      path,
      manifest,
      ipc_config,
      commands,
      extension_registry=framework_registry,
    ) {
    Err(error) => abort(error)
    Ok(_) => ()
  }
  @mbfs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "framework ipc config writer records user-parent launch settings" {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  let path = "target/framework-ipc-wbtest.json"
  let manifest = demo_manifest({})
  let commands = AppCommandsConfig::new(["app:ping"])
  let ipc_config = match
    make_framework_ipc_launch_config(Some("ipc-test-token")) {
    Err(error) => abort(error)
    Ok(config) => config
  }
  match
    write_framework_process_ipc_config(path, manifest, ipc_config, commands) {
    Err(error) => abort(error)
    Ok(_) => ()
  }
  let config = match read_framework_config(path) {
    Err(error) => abort(error)
    Ok(config) => config
  }
  assert_eq(config.version, framework_config_version)
  match config.ipc {
    Some(ipc) => assert_eq(ipc.token, "ipc-test-token")
    None => abort("expected ipc launch config")
  }
  @debug.assert_eq(config.op_names, ["app:ping"])
  @mbfs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "framework config validation rejects invalid command metadata" {
  let unsupported_version = FrameworkProcessConfig::{
    version: framework_config_version + 1,
    manifest: Json::object({}),
    base_dir: None,
    ipc: None,
    op_names: ["app:ping"],
    extensions: [],
    framework_extension_ids: [],
  }
  match validate_framework_process_config(unsupported_version) {
    Err(error) =>
      assert_eq(
        error,
        "unsupported framework config version: " +
        (framework_config_version + 1).to_string(),
      )
    Ok(_) => abort("expected unsupported framework config version error")
  }

  let duplicate_ops = FrameworkProcessConfig::{
    version: framework_config_version,
    manifest: Json::object({}),
    base_dir: None,
    ipc: Some(@ipc_ws.WsIpcLaunchConfig::new("test-token", [49181])),
    op_names: ["app:ping", "app:ping"],
    extensions: [],
    framework_extension_ids: [],
  }
  match validate_framework_process_config(duplicate_ops) {
    Err(error) =>
      assert_eq(
        error, "invalid framework config commands: duplicate app command op name: app:ping",
      )
    Ok(_) => abort("expected duplicate op validation error")
  }

  let mismatched_descriptor = FrameworkProcessConfig::{
    version: framework_config_version,
    manifest: Json::object({}),
    base_dir: None,
    ipc: Some(@ipc_ws.WsIpcLaunchConfig::new("test-token", [49181])),
    op_names: ["ext:demo/other"],
    extensions: [
      @ipc.IpcExtensionDescriptor::new("vendor/demo", "demo", [
        @ipc.IpcExtensionApi::new("ping"),
      ]),
    ],
    framework_extension_ids: [],
  }
  match validate_framework_process_config(mismatched_descriptor) {
    Err(error) =>
      assert_eq(
        error, "invalid framework config commands: command extension descriptor API is missing op: ext:demo/ping",
      )
    Ok(_) => abort("expected descriptor mismatch validation error")
  }
}

///|
test "command extension can depend on framework extension" {
  let framework_registry = ExtensionRegistry::new().register(
    stub_extension("justjavac/lepus-path", js_namespace=Some("path")),
  )
  let command_registry = AppCommandExtensionRegistry::new().register(
    stub_command_extension("examples/async-add", js_namespace=Some("add"), dependencies=[
      "justjavac/lepus-path",
    ]),
  )
  let manifest = demo_manifest({
    "examples/async-add": @manifest.ExtensionSetting::enabled(),
  })
  let prepared = match
    plan_app_command_extensions(
      manifest,
      command_registry,
      extension_registry=framework_registry,
    ) {
    Ok(prepared) => prepared
    Err(error) => abort(error)
  }
  let commands = app_commands_config_from_prepared(
    prepared,
    framework_registry.spec_map(),
  )
  @debug.assert_eq(commands.framework_extension_ids(), ["justjavac/lepus-path"])
  let framework_manifest = framework_manifest_for_commands(
    manifest, framework_registry, commands,
  )
  @debug.assert_eq(
    framework_manifest.extension_setting("justjavac/lepus-path"),
    Some(@manifest.ExtensionSetting::enabled()),
  )
}

///|
test "command extension rejects disabled framework dependency" {
  let framework_registry = ExtensionRegistry::new().register(
    stub_extension("justjavac/lepus-path", js_namespace=Some("path")),
  )
  let command_registry = AppCommandExtensionRegistry::new().register(
    stub_command_extension("examples/async-add", js_namespace=Some("add"), dependencies=[
      "justjavac/lepus-path",
    ]),
  )
  let manifest = demo_manifest({
    "justjavac/lepus-path": @manifest.ExtensionSetting::disabled(),
    "examples/async-add": @manifest.ExtensionSetting::enabled(),
  })
  match
    plan_app_command_extensions(
      manifest,
      command_registry,
      extension_registry=framework_registry,
    ) {
    Err(error) =>
      assert_eq(
        error, "command extension examples/async-add requires disabled framework dependency justjavac/lepus-path",
      )
    Ok(_) => abort("expected disabled framework dependency error")
  }
}

///|
test "command extension rejects disabled command dependency" {
  let command_registry = AppCommandExtensionRegistry::new()
    .register(stub_command_extension("vendor/base", js_namespace=Some("base")))
    .register(
      stub_command_extension("vendor/feature", js_namespace=Some("feature"), dependencies=[
        "vendor/base",
      ]),
    )
  let manifest = demo_manifest({
    "vendor/base": @manifest.ExtensionSetting::disabled(),
    "vendor/feature": @manifest.ExtensionSetting::enabled(),
  })
  match plan_app_command_extensions(manifest, command_registry) {
    Err(error) =>
      assert_eq(
        error, "command extension vendor/feature requires disabled dependency vendor/base",
      )
    Ok(_) => abort("expected disabled command dependency error")
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
test "prepare_app rejects invalid dependency shape" {
  let manifest = demo_manifest({
    "vendor/feature": @manifest.ExtensionSetting::enabled(),
  })
  let empty_dependency = ExtensionRegistry::new().register(
    stub_extension("vendor/feature", dependencies=[" "]),
  )
  match prepare_app(manifest, empty_dependency) {
    Err(error) =>
      assert_eq(error, "extension dependency must not be empty: vendor/feature")
    Ok(_) => abort("expected empty extension dependency error")
  }

  let self_dependency = ExtensionRegistry::new().register(
    stub_extension("vendor/feature", dependencies=["vendor/feature"]),
  )
  match prepare_app(manifest, self_dependency) {
    Err(error) =>
      assert_eq(error, "extension must not depend on itself: vendor/feature")
    Ok(_) => abort("expected self extension dependency error")
  }

  let duplicate_dependency = ExtensionRegistry::new().register(
    stub_extension("vendor/feature", dependencies=["vendor/base", "vendor/base"]),
  )
  match prepare_app(manifest, duplicate_dependency) {
    Err(error) =>
      assert_eq(
        error, "duplicate extension dependency: vendor/feature -> vendor/base",
      )
    Ok(_) => abort("expected duplicate extension dependency error")
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
test "app commands config preserves command extension descriptors" {
  let extension = AppCommandExtensionDescriptor::new("vendor/demo", "demo", [
    AppCommandApiDescriptor::new("ping"),
  ])
  let commands = AppCommandsConfig::new(["app:ping"], extensions=[extension])
  @debug.assert_eq(commands.op_names(), ["app:ping"])
  assert_eq(commands.extensions().length(), 1)
  assert_eq(commands.extensions()[0].id, "vendor/demo")
}

///|
test "app command constructors copy mutable array inputs" {
  let op_names = ["ext:demo/ping"]
  let framework_ids = ["vendor/framework"]
  let apis = [AppCommandApiDescriptor::new("ping")]
  let scripts = ["window.__demo = true;"]
  let extension = AppCommandExtensionDescriptor::new(
    "vendor/demo",
    "demo",
    apis,
    scripts~,
  )
  let commands = AppCommandsConfig::new(
    op_names,
    extensions=[extension],
    framework_extension_ids=framework_ids,
  )

  op_names.push(" ")
  framework_ids.push(" ")
  apis.push(AppCommandApiDescriptor::new("later"))
  scripts.push("window.__demo = false;")

  match validate_app_commands_config(commands) {
    Ok(_) => ()
    Err(error) => abort(error)
  }
  @debug.assert_eq(commands.op_names(), ["ext:demo/ping"])
  @debug.assert_eq(commands.framework_extension_ids(), ["vendor/framework"])
  assert_eq(commands.extensions()[0].apis.length(), 1)
  assert_eq(commands.extensions()[0].scripts.length(), 1)
}

///|
test "app commands config exposes command descriptor snapshots" {
  let commands = AppCommandsConfig::new(["ext:demo/ping"], extensions=[
    AppCommandExtensionDescriptor::new(
      "vendor/demo",
      "demo",
      [AppCommandApiDescriptor::new("ping")],
      scripts=["window.__demo = true;"],
    ),
  ])
  let descriptors = commands.extensions()
  descriptors[0].apis.push(@ipc.IpcExtensionApi::new("changed"))
  descriptors[0].scripts.push("window.__demo = false;")

  let snapshot = commands.extensions()
  assert_eq(snapshot.length(), 1)
  assert_eq(snapshot[0].apis.length(), 1)
  assert_eq(snapshot[0].scripts.length(), 1)
}

///|
test "framework config command conversion copies descriptor arrays" {
  let descriptor = @ipc.IpcExtensionDescriptor::new("vendor/demo", "demo", [
    @ipc.IpcExtensionApi::new("ping"),
  ])
  let config = FrameworkProcessConfig::{
    version: framework_config_version,
    manifest: Json::object({}),
    base_dir: None,
    ipc: Some(@ipc_ws.WsIpcLaunchConfig::new("test-token", [49181])),
    op_names: ["ext:demo/ping"],
    extensions: [descriptor],
    framework_extension_ids: [],
  }
  let commands = app_commands_config_from_framework_config(config)
  descriptor.apis.push(@ipc.IpcExtensionApi::new("changed"))

  let snapshot = commands.extensions()
  assert_eq(snapshot.length(), 1)
  assert_eq(snapshot[0].apis.length(), 1)
}

///|
test "extension registries expose snapshot id lists" {
  let extension_registry = ExtensionRegistry::new().register(
    stub_extension("vendor/framework", js_namespace=Some("framework")),
  )
  let extension_ids = extension_registry.registered_ids()
  extension_ids.push("vendor/mutated")
  @debug.assert_eq(extension_registry.registered_ids(), ["vendor/framework"])

  let command_registry = AppCommandExtensionRegistry::new().register(
    stub_command_extension("vendor/demo", js_namespace=Some("demo")),
  )
  let command_ids = command_registry.registered_ids()
  command_ids.push("vendor/mutated")
  @debug.assert_eq(command_registry.registered_ids(), ["vendor/demo"])
}

///|
test "command extension spec exposes dependency snapshots" {
  let dependencies = ["vendor/base"]
  let spec = AppCommandExtensionSpec::new(
    "vendor/demo",
    "demo",
    [AppCommandApiDescriptor::new("ping")],
    fn(_context) { Ok(()) },
    dependencies~,
  )
  dependencies.push("vendor/mutated")
  @debug.assert_eq(spec.dependencies(), ["vendor/base"])
  let exposed = spec.dependencies()
  exposed.push("vendor/changed")
  @debug.assert_eq(spec.dependencies(), ["vendor/base"])
}

///|
test "command extension registry and prepared entries copy specs" {
  let destroy_count = Ref(0)
  let spec = AppCommandExtensionSpec::new(
    "vendor/demo",
    "demo",
    [AppCommandApiDescriptor::new("ping")],
    fn(_context) { Ok(()) },
    scripts=["window.__demo = true;"],
    dependencies=["vendor/base"],
    on_destroy=fn(_context) { destroy_count.val += 1 },
  )
  let registry = AppCommandExtensionRegistry::new().register(spec)
  spec.apis.push(AppCommandApiDescriptor::new("changed"))
  spec.scripts.push("window.__demo = false;")
  spec.dependencies.push("vendor/mutated")

  let registered = match registry.get("vendor/demo") {
    Some(value) => value
    None => abort("expected registered command extension")
  }
  @debug.assert_eq(registered.op_names(), ["ext:demo/ping"])
  @debug.assert_eq(registered.dependencies(), ["vendor/base"])
  let descriptor = registered.to_ipc_descriptor()
  assert_eq(descriptor.scripts.length(), 1)

  registered.apis.push(AppCommandApiDescriptor::new("later"))
  registered.scripts.push("window.__demo = null;")
  registered.dependencies.push("vendor/changed")
  let fresh = match registry.get("vendor/demo") {
    Some(value) => value
    None => abort("expected fresh registered command extension")
  }
  @debug.assert_eq(fresh.op_names(), ["ext:demo/ping"])
  @debug.assert_eq(fresh.dependencies(), ["vendor/base"])
  assert_eq(fresh.to_ipc_descriptor().scripts.length(), 1)
  let host = @core.AppCommandHost::new()
  let context = AppCommandExtensionContext::new(host, "vendor/demo", "demo")
  fresh.destroy(context)
  assert_eq(destroy_count.val, 1)
  host.close()

  let prepared = PreparedAppCommandExtension::new(
    "vendor/demo",
    fresh,
    Some(Json::object({ "enabled": Json::boolean(true) })),
  )
  fresh.apis.push(AppCommandApiDescriptor::new("after-prepare"))
  @debug.assert_eq(prepared.spec().op_names(), ["ext:demo/ping"])
  let exposed = prepared.spec()
  exposed.apis.push(AppCommandApiDescriptor::new("exposed"))
  @debug.assert_eq(prepared.spec().op_names(), ["ext:demo/ping"])
}

///|
test "prepared sync extension options are snapshots" {
  let options = Json::object({ "scope": Json::string("read") })
  let prepared = PreparedExtension::new(
    "vendor/framework",
    stub_extension("vendor/framework", js_namespace=Some("framework")),
    Some(options),
  )
  match options {
    Object(object) => object["late"] = Json::boolean(true)
    _ => abort("expected object options")
  }
  match prepared.options() {
    Some(Object(object)) => {
      @debug.assert_eq(object.get("late"), None)
      object["exposed"] = Json::boolean(true)
    }
    _ => abort("expected prepared extension options")
  }
  match prepared.options() {
    Some(Object(object)) => @debug.assert_eq(object.get("exposed"), None)
    _ => abort("expected fresh prepared extension options")
  }
  let prepared_app = PreparedApp::new(
    runtime_config_from_manifest(
      @manifest.AppManifest::new(
        @manifest.WindowManifest::new("Main", 800, 600),
        @manifest.AppEntry::Html("<html></html>"),
      ),
    ),
    [prepared],
  )
  let exposed = prepared_app.prepared_extensions()
  ignore(
    exposed[0]
    .options()
    .map(fn(json) {
      match json {
        Object(object) => object["from-list"] = Json::boolean(true)
        _ => ()
      }
    }),
  )
  match prepared_app.prepared_extensions()[0].options() {
    Some(Object(object)) => @debug.assert_eq(object.get("from-list"), None)
    _ => abort("expected prepared app extension options")
  }
}

///|
test "command extension context and prepared options are snapshots" {
  let options = Json::object({ "mode": Json::string("fast") })
  let spec = AppCommandExtensionSpec::new(
    "vendor/demo",
    "demo",
    [AppCommandApiDescriptor::new("ping")],
    fn(_context) { Ok(()) },
  )
  let prepared = PreparedAppCommandExtension::new(
    "vendor/demo",
    spec,
    Some(options),
  )
  match options {
    Object(object) => object["late"] = Json::boolean(true)
    _ => abort("expected object options")
  }
  match prepared.options() {
    Some(Object(object)) => {
      @debug.assert_eq(object.get("late"), None)
      object["exposed"] = Json::boolean(true)
    }
    _ => abort("expected prepared command options")
  }
  match prepared.options() {
    Some(Object(object)) => @debug.assert_eq(object.get("exposed"), None)
    _ => abort("expected fresh prepared command options")
  }

  let host = @core.AppCommandHost::new()
  let context = AppCommandExtensionContext::new(
    host,
    "vendor/demo",
    "demo",
    options=prepared.options(),
  )
  match context.options() {
    Some(Object(object)) => object["context"] = Json::boolean(true)
    _ => abort("expected command context options")
  }
  match context.options() {
    Some(Object(object)) => @debug.assert_eq(object.get("context"), None)
    _ => abort("expected fresh command context options")
  }
  host.close()
}

///|
test "app commands config rejects duplicate op names" {
  let commands = AppCommandsConfig::new(["app:ping", "app:ping"])
  match validate_app_commands_config(commands) {
    Err(error) => assert_eq(error, "duplicate app command op name: app:ping")
    Ok(_) => abort("expected duplicate op name error")
  }
}

///|
test "app commands config rejects invalid framework dependency ids" {
  let empty = AppCommandsConfig::new(["app:ping"], framework_extension_ids=[
    "justjavac/lepus-path", " ",
  ])
  match validate_app_commands_config(empty) {
    Err(error) =>
      assert_eq(error, "command framework dependency id must not be empty")
    Ok(_) => abort("expected empty framework dependency id error")
  }

  let duplicate = AppCommandsConfig::new(["app:ping"], framework_extension_ids=[
    "justjavac/lepus-path", "justjavac/lepus-path",
  ])
  match validate_app_commands_config(duplicate) {
    Err(error) =>
      assert_eq(
        error, "duplicate command framework dependency: justjavac/lepus-path",
      )
    Ok(_) => abort("expected duplicate framework dependency id error")
  }
}

///|
test "framework ipc config accepts caller provided token" {
  match make_framework_ipc_launch_config(Some("external-random-token")) {
    Ok(config) => assert_eq(config.ws.token, "external-random-token")
    Err(error) => abort(error)
  }
  match make_framework_ipc_launch_config(Some("  ")) {
    Err(error) => assert_eq(error, "WebSocket IPC token must not be empty")
    Ok(_) => abort("expected empty token error")
  }
  match make_framework_ipc_launch_config(Some("令牌")) {
    Err(error) =>
      assert_eq(error, "WebSocket IPC token must be printable ASCII")
    Ok(_) => abort("expected non-ASCII token error")
  }
}

///|
test "framework config path prefers cli args over env" {
  @debug.assert_eq(
    framework_config_path(
      ["app.exe", "--lepus-framework-config", "from-args.json"],
      Some("from-env.json"),
    ),
    Ok("from-args.json"),
  )
  @debug.assert_eq(
    framework_config_path(["app.exe"], Some("from-env.json")),
    Ok("from-env.json"),
  )
  @debug.assert_eq(
    framework_config_path(
      ["app.exe", "--lepus-framework-config", ""],
      Some("from-env.json"),
    ),
    Err("framework config path must not be empty"),
  )
  @debug.assert_eq(
    framework_config_path(
      ["app.exe", "--lepus-framework-config"],
      Some("from-env.json"),
    ),
    Err("missing value for --lepus-framework-config"),
  )
  @debug.assert_eq(
    framework_config_path(
      [
        "app.exe", "--lepus-framework-config", "first.json", "--lepus-framework-config",
        "second.json",
      ],
      Some("from-env.json"),
    ),
    Err("duplicate value for --lepus-framework-config"),
  )
  @debug.assert_eq(
    framework_config_path(["app.exe"], Some("")),
    Err(missing_framework_config_message()),
  )
}

///|
test "app commands config rejects descriptor APIs without matching ops" {
  let extension = AppCommandExtensionDescriptor::new("vendor/demo", "demo", [
    AppCommandApiDescriptor::new("ping"),
  ])
  let commands = AppCommandsConfig::new(["ext:demo/pong"], extensions=[
    extension,
  ])
  match validate_app_commands_config(commands) {
    Err(error) =>
      assert_eq(
        error, "command extension descriptor API is missing op: ext:demo/ping",
      )
    Ok(_) => abort("expected descriptor op mismatch error")
  }
}

///|
test "app commands config rejects extension ops without descriptors" {
  let missing_descriptor = AppCommandsConfig::new(["ext:demo/ping"])
  match validate_app_commands_config(missing_descriptor) {
    Err(error) =>
      assert_eq(
        error, "command extension op is missing descriptor: ext:demo/ping",
      )
    Ok(_) => abort("expected missing command extension descriptor error")
  }

  let extension = AppCommandExtensionDescriptor::new("vendor/demo", "demo", [
    AppCommandApiDescriptor::new("ping"),
  ])
  let extra_op = AppCommandsConfig::new(["ext:demo/ping", "ext:demo/secret"], extensions=[
    extension,
  ])
  match validate_app_commands_config(extra_op) {
    Err(error) =>
      assert_eq(
        error, "command extension op is missing descriptor: ext:demo/secret",
      )
    Ok(_) => abort("expected undeclared command extension op error")
  }
}

///|
test "command extension planning rejects duplicate namespaces" {
  let registry = AppCommandExtensionRegistry::new()
    .register(stub_command_extension("vendor/alpha", js_namespace=Some("demo")))
    .register(stub_command_extension("vendor/beta", js_namespace=Some("demo")))
  let manifest = demo_manifest({
    "vendor/alpha": @manifest.ExtensionSetting::enabled(),
    "vendor/beta": @manifest.ExtensionSetting::enabled(),
  })
  match plan_app_command_extensions(manifest, registry) {
    Err(error) =>
      assert_eq(
        error, "command extension vendor/beta reuses namespace demo from vendor/alpha",
      )
    Ok(_) => abort("expected duplicate command extension namespace error")
  }
}

///|
test "command extension planning rejects framework id collisions" {
  let extension_registry = ExtensionRegistry::new().register(
    stub_extension("vendor/shared", js_namespace=Some("sharedFramework")),
  )
  let command_registry = AppCommandExtensionRegistry::new().register(
    stub_command_extension("vendor/shared", js_namespace=Some("sharedCommand")),
  )
  let manifest = demo_manifest({
    "vendor/shared": @manifest.ExtensionSetting::enabled(),
  })
  match
    plan_app_command_extensions(manifest, command_registry, extension_registry~) {
    Err(error) =>
      assert_eq(
        error, "command extension id collides with framework extension id: vendor/shared",
      )
    Ok(_) => abort("expected framework command extension id collision")
  }
}

///|
test "raw app commands reject framework id collisions" {
  let extension_registry = ExtensionRegistry::new().register(
    stub_extension("vendor/shared", js_namespace=Some("sharedFramework")),
  )
  let command_extension = AppCommandExtensionDescriptor::new(
    "vendor/shared",
    "sharedCommand",
    [AppCommandApiDescriptor::new("ping")],
  )
  let commands = AppCommandsConfig::new(["ext:sharedCommand/ping"], extensions=[
    command_extension,
  ])
  let manifest = demo_manifest({
    "vendor/shared": @manifest.ExtensionSetting::enabled(),
  })
  match
    validate_framework_manifest_extensions(
      manifest, extension_registry, commands,
    ) {
    Err(error) =>
      assert_eq(
        error, "command extension id collides with framework extension id: vendor/shared",
      )
    Ok(_) => abort("expected raw app command framework id collision")
  }
}

///|
test "raw app commands reject enabled framework namespace collisions" {
  let extension_registry = ExtensionRegistry::new().register(
    stub_extension("vendor/framework", js_namespace=Some("shared")),
  )
  let command_extension = AppCommandExtensionDescriptor::new(
    "vendor/command",
    "shared",
    [AppCommandApiDescriptor::new("ping")],
  )
  let commands = AppCommandsConfig::new(["ext:shared/ping"], extensions=[
    command_extension,
  ])
  let manifest = demo_manifest({
    "vendor/framework": @manifest.ExtensionSetting::enabled(),
    "vendor/command": @manifest.ExtensionSetting::enabled(),
  })
  match
    validate_framework_manifest_extensions(
      manifest, extension_registry, commands,
    ) {
    Err(error) =>
      assert_eq(
        error, "command extension namespace collides with framework extension namespace: vendor/command -> shared",
      )
    Ok(_) => abort("expected enabled framework namespace collision")
  }
}

///|
test "raw app commands reject framework dependency namespace collisions" {
  let extension_registry = ExtensionRegistry::new().register(
    stub_extension("vendor/framework", js_namespace=Some("shared")),
  )
  let command_extension = AppCommandExtensionDescriptor::new(
    "vendor/command",
    "shared",
    [AppCommandApiDescriptor::new("ping")],
  )
  let commands = AppCommandsConfig::new(
    ["ext:shared/ping"],
    extensions=[command_extension],
    framework_extension_ids=["vendor/framework"],
  )
  let manifest = demo_manifest({
    "vendor/command": @manifest.ExtensionSetting::enabled(),
  })
  match
    validate_framework_manifest_extensions(
      manifest, extension_registry, commands,
    ) {
    Err(error) =>
      assert_eq(
        error, "command extension namespace collides with framework extension namespace: vendor/command -> shared",
      )
    Ok(_) => abort("expected framework dependency namespace collision")
  }
}

///|
test "raw app commands reject op name separators in descriptor public names" {
  let extension_registry = ExtensionRegistry::new()
  let manifest = demo_manifest({
    "vendor/command": @manifest.ExtensionSetting::enabled(),
  })
  let namespace_command = AppCommandsConfig::new(["ext:demo/bad/ping"], extensions=[
    AppCommandExtensionDescriptor::new("vendor/command", "demo/bad", [
      AppCommandApiDescriptor::new("ping"),
    ]),
  ])
  match
    validate_framework_manifest_extensions(
      manifest, extension_registry, namespace_command,
    ) {
    Err(error) =>
      assert_eq(
        error, "command extension descriptor namespace must not contain '/': demo/bad",
      )
    Ok(_) => abort("expected raw namespace separator error")
  }

  let api_command = AppCommandsConfig::new(["ext:demo/bad/api"], extensions=[
    AppCommandExtensionDescriptor::new("vendor/command", "demo", [
      AppCommandApiDescriptor::new("bad/api"),
    ]),
  ])
  match
    validate_framework_manifest_extensions(
      manifest, extension_registry, api_command,
    ) {
    Err(error) =>
      assert_eq(
        error, "command extension descriptor API name must not contain '/': vendor/command.bad/api",
      )
    Ok(_) => abort("expected raw API separator error")
  }
}

///|
test "raw app commands reject transitive framework namespace collisions" {
  let extension_registry = ExtensionRegistry::new()
    .register(stub_extension("vendor/base", js_namespace=Some("shared")))
    .register(
      stub_extension("vendor/framework", js_namespace=Some("framework"), dependencies=[
        "vendor/base",
      ]),
    )
  let command_extension = AppCommandExtensionDescriptor::new(
    "vendor/command",
    "shared",
    [AppCommandApiDescriptor::new("ping")],
  )
  let commands = AppCommandsConfig::new(["ext:shared/ping"], extensions=[
    command_extension,
  ])
  let manifest = demo_manifest({
    "vendor/framework": @manifest.ExtensionSetting::enabled(),
    "vendor/command": @manifest.ExtensionSetting::enabled(),
  })
  match
    validate_framework_manifest_extensions(
      manifest, extension_registry, commands,
    ) {
    Err(error) =>
      assert_eq(
        error, "command extension namespace collides with framework extension namespace: vendor/command -> shared",
      )
    Ok(_) => abort("expected transitive framework namespace collision")
  }
}

///|
test "command extension planning rejects empty API lists" {
  let registry = AppCommandExtensionRegistry::new().register(
    AppCommandExtensionSpec::new("vendor/empty", "empty", [], fn(_context) {
      Ok(())
    }),
  )
  let manifest = demo_manifest({
    "vendor/empty": @manifest.ExtensionSetting::enabled(),
  })
  match plan_app_command_extensions(manifest, registry) {
    Err(error) =>
      assert_eq(
        error, "command extension must expose at least one API: vendor/empty",
      )
    Ok(_) => abort("expected empty command extension API error")
  }
}

///|
test "command extension planning rejects invalid dependency shape" {
  let empty_dependency = AppCommandExtensionRegistry::new().register(
    stub_command_extension("vendor/feature", js_namespace=Some("feature"), dependencies=[
      " ",
    ]),
  )
  let manifest = demo_manifest({
    "vendor/feature": @manifest.ExtensionSetting::enabled(),
  })
  match plan_app_command_extensions(manifest, empty_dependency) {
    Err(error) =>
      assert_eq(
        error, "command extension dependency must not be empty: vendor/feature",
      )
    Ok(_) => abort("expected empty command extension dependency error")
  }

  let self_dependency = AppCommandExtensionRegistry::new().register(
    stub_command_extension("vendor/feature", js_namespace=Some("feature"), dependencies=[
      "vendor/feature",
    ]),
  )
  match plan_app_command_extensions(manifest, self_dependency) {
    Err(error) =>
      assert_eq(
        error, "command extension must not depend on itself: vendor/feature",
      )
    Ok(_) => abort("expected self command extension dependency error")
  }

  let duplicate_dependency = AppCommandExtensionRegistry::new().register(
    stub_command_extension("vendor/feature", js_namespace=Some("feature"), dependencies=[
      "vendor/base", "vendor/base",
    ]),
  )
  match plan_app_command_extensions(manifest, duplicate_dependency) {
    Err(error) =>
      assert_eq(
        error, "duplicate command extension dependency: vendor/feature -> vendor/base",
      )
    Ok(_) => abort("expected duplicate command extension dependency error")
  }
}

///|
test "command extension planning rejects op name separators in public names" {
  let namespace_registry = AppCommandExtensionRegistry::new().register(
    stub_command_extension("vendor/demo", js_namespace=Some("demo/bad")),
  )
  let manifest = demo_manifest({
    "vendor/demo": @manifest.ExtensionSetting::enabled(),
  })
  match plan_app_command_extensions(manifest, namespace_registry) {
    Err(error) =>
      assert_eq(
        error, "command extension namespace must not contain '/': demo/bad",
      )
    Ok(_) => abort("expected command namespace separator error")
  }

  let api_registry = AppCommandExtensionRegistry::new().register(
    AppCommandExtensionSpec::new(
      "vendor/demo",
      "demo",
      [AppCommandApiDescriptor::new("bad/api")],
      fn(_context) { Ok(()) },
    ),
  )
  match plan_app_command_extensions(manifest, api_registry) {
    Err(error) =>
      assert_eq(
        error, "command extension API name must not contain '/': vendor/demo.bad/api",
      )
    Ok(_) => abort("expected command API separator error")
  }
}

///|
test "command extension host rejects missing declared handlers" {
  let registry = AppCommandExtensionRegistry::new().register(
    stub_command_extension("vendor/demo", js_namespace=Some("demo")),
  )
  let manifest = demo_manifest({
    "vendor/demo": @manifest.ExtensionSetting::enabled(),
  })
  let prepared = match plan_app_command_extensions(manifest, registry) {
    Err(error) => abort(error)
    Ok(prepared) => prepared
  }
  let host = @core.AppCommandHost::new()
  match validate_registered_command_extension_handlers(prepared, host) {
    Err(error) =>
      assert_eq(
        error, "command extension vendor/demo did not register handler for ext:demo/ping",
      )
    Ok(_) => abort("expected missing declared handler error")
  }
  host.close()
}

///|
test "command extension host rejects undeclared handlers" {
  let registry = AppCommandExtensionRegistry::new().register(
    stub_command_extension("vendor/demo", js_namespace=Some("demo")),
  )
  let manifest = demo_manifest({
    "vendor/demo": @manifest.ExtensionSetting::enabled(),
  })
  let prepared = match plan_app_command_extensions(manifest, registry) {
    Err(error) => abort(error)
    Ok(prepared) => prepared
  }
  let host = @core.AppCommandHost::new()
  host.op("ext:demo/ping", fn(_payload : Json) { Json::null() })
  host.op("ext:demo/secret", fn(_payload : Json) { Json::null() })
  match validate_registered_command_extension_handlers(prepared, host) {
    Err(error) =>
      assert_eq(
        error, "command extension registered undeclared handler: ext:demo/secret",
      )
    Ok(_) => abort("expected undeclared command handler error")
  }
  host.close()
}
