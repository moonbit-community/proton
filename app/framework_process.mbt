///|
let framework_config_arg_name = "--lepus-framework-config"

///|
let framework_config_env_name = "LEPUS_FRAMEWORK_CONFIG"

///|
let framework_process_arg_name = "--lepus-framework-process"

///|
let framework_config_version = 2

///|
priv struct FrameworkProcessConfig {
  version : Int
  manifest : Json
  base_dir : String?
  ipc : @ipc_ws.WsIpcLaunchConfig?
  op_names : Array[String]
  extensions : Array[@ipc.IpcExtensionDescriptor]
  framework_extension_ids : Array[String]
} derive(ToJson, FromJson)

///|
/// Returns the CLI flag used when the current executable should enter
/// framework/webview mode.
pub fn framework_process_arg() -> String {
  framework_process_arg_name
}

///|
/// Returns whether the current process was started as the framework process.
pub fn is_framework_process() -> Bool {
  @sys.get_cli_args().any(fn(arg) { arg == framework_process_arg_name })
}

///|
/// Returns the current executable command as reported by argv[0].
///
/// Single-binary examples use this to start the same executable again in
/// framework mode with `--lepus-framework-process`.
pub fn current_executable_command() -> Result[String, String] {
  match @sys.get_cli_args().get(0) {
    Some(command) if command.trim().to_owned() != "" => Ok(command)
    _ => Err("current executable command is unavailable")
  }
}

///|
/// Runs user-side command handlers and starts a framework/webview process.
///
/// The current process owns user code and async handlers. `framework_command`
/// is started as a child process and should run
/// `run_framework_process_from_cli(...)`.
pub fn run_app_command_host_with_framework_process(
  manifest : @manifest.AppManifest,
  framework_command : String,
  host : @core.AppCommandHost,
  commands : AppCommandsConfig,
  extension_registry? : ExtensionRegistry = ExtensionRegistry::new(),
  framework_args? : Array[String] = [],
  framework_cwd? : String? = None,
  base_dir? : String? = None,
  ipc_token? : String? = None,
  framework_config_path? : String? = None,
) -> Result[Unit, String] {
  match validate_framework_process_command(framework_command) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match validate_app_commands_config(commands) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match
    validate_framework_manifest_extensions(
      manifest, extension_registry, commands,
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let ipc_config = match make_framework_ipc_launch_config(ipc_token) {
    Ok(config) => config
    Err(error) => return Err(error)
  }
  let config_path = match framework_config_path {
    Some(path) => path
    None => default_framework_process_config_path(ipc_config)
  }
  match
    write_framework_process_ipc_config(
      config_path,
      manifest,
      ipc_config,
      commands,
      base_dir~,
      extension_registry~,
    ) {
    Err(error) => {
      host.close()
      return Err(error)
    }
    Ok(_) => ()
  }
  let args = framework_launch_args(framework_args, config_path)
  let mut result : Result[Unit, String] = Err("framework process did not run")
  @async.run_async_main(async fn() {
    result = run_app_command_host_with_framework_process_async(
      host, framework_command, args, framework_cwd, ipc_config,
    )
  })
  result
}

///|
async fn run_app_command_host_with_framework_process_async(
  host : @core.AppCommandHost,
  framework_command : String,
  framework_args : Array[String],
  framework_cwd : String?,
  ipc_config : FrameworkIpcLaunchConfig,
) -> Result[Unit, String] {
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      ignore(run_framework_ipc_command_host_with_config(host, ipc_config))
    })
    match wait_framework_ipc_ready(ipc_config) {
      Err(error) => {
        host.close()
        return Err(error)
      }
      Ok(_) => ()
    }
    let child = match framework_cwd {
      Some(cwd) =>
        spawn_framework_process_in_group(
          group,
          framework_command,
          args=framework_args,
          cwd~,
        )
      None =>
        spawn_framework_process_in_group(
          group,
          framework_command,
          args=framework_args,
        )
    }
    let child = match child {
      Err(error) => {
        host.close()
        return Err(error)
      }
      Ok(child) => child
    }
    let mut child_reaped = false
    defer (if !child_reaped { child.cancel() })
    let exit_code = child.wait()
    child_reaped = true
    host.close()
    if exit_code == 0 {
      Ok(())
    } else {
      Err("framework process exited with code " + exit_code.to_string())
    }
  })
}

///|
/// Runs the framework runtime process using CLI or environment configuration.
///
/// Framework binaries can use this as their `main` body. The config is written
/// by the user process that owns command handlers and IPC server lifetime.
pub fn run_framework_process_from_cli(
  extension_registry? : ExtensionRegistry = ExtensionRegistry::new(),
) -> Result[Unit, String] {
  match framework_config_path_from_env_or_args() {
    Err(error) => Err(error)
    Ok(path) =>
      run_framework_process_from_config_file(path, extension_registry~)
  }
}

///|
/// Runs the framework runtime process from one serialized config file.
pub fn run_framework_process_from_config_file(
  path : String,
  extension_registry? : ExtensionRegistry = ExtensionRegistry::new(),
) -> Result[Unit, String] {
  read_framework_config(path).bind(fn(config) {
    run_framework_process(config, extension_registry)
  })
}

///|
fn run_framework_process(
  config : FrameworkProcessConfig,
  extension_registry : ExtensionRegistry,
) -> Result[Unit, String] {
  validate_framework_process_config(config).bind(fn(_) {
    @bootstrap.load_app_manifest_from_json(config.manifest.stringify()).bind(fn(
      loaded,
    ) {
      let base_dir = match config.base_dir {
        Some(base_dir) => Some(base_dir)
        None => loaded.base_dir()
      }
      let commands = app_commands_config_from_framework_config(config)
      match config.ipc {
        Some(ipc) =>
          run_framework_app_process(
            loaded.manifest(),
            framework_ipc_launch_config_from_ws(ipc),
            commands,
            extension_registry,
            base_dir~,
          )
        None => Err("framework config ipc must be present")
      }
    })
  })
}

///|
fn run_framework_app_process(
  manifest : @manifest.AppManifest,
  ipc_config : FrameworkIpcLaunchConfig,
  commands : AppCommandsConfig,
  extension_registry : ExtensionRegistry,
  base_dir? : String? = None,
) -> Result[Unit, String] {
  match validate_app_commands_config(commands) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match
    validate_framework_manifest_extensions(
      manifest, extension_registry, commands,
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let framework_manifest = framework_manifest_for_commands(
    manifest, extension_registry, commands,
  )
  match create_app(framework_manifest, extension_registry, base_dir~) {
    Err(error) => Err(error)
    Ok(app) => {
      let bridge_script = make_framework_ipc_bridge_script(
        ipc_config,
        commands.op_names(),
      )
      app.install_ipc_bridge(
        bridge_script,
        commands.op_names(),
        extensions=commands.extensions(),
      )
      app.run()
      Ok(())
    }
  }
}

///|
fn validate_framework_process_command(command : String) -> Result[Unit, String] {
  guard command.trim().to_owned() != "" else {
    return Err("framework process command must not be empty")
  }
  Ok(())
}

///|
fn validate_app_commands_config(
  commands : AppCommandsConfig,
) -> Result[Unit, String] {
  guard commands.op_names().length() > 0 else {
    return Err("app commands must expose at least one op")
  }
  let op_names : Map[String, Bool] = {}
  for op_name in commands.op_names() {
    guard op_name.trim().to_owned() != "" else {
      return Err("app command op name must not be empty")
    }
    guard op_names.get(op_name) is None else {
      return Err("duplicate app command op name: " + op_name)
    }
    op_names[op_name] = true
  }
  let extension_ids : Map[String, Bool] = {}
  let extension_namespaces : Map[String, Bool] = {}
  let extension_op_names : Map[String, Bool] = {}
  for descriptor in commands.extensions() {
    match
      validate_app_command_descriptor(
        descriptor, op_names, extension_ids, extension_namespaces, extension_op_names,
      ) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  match
    validate_extension_op_names_have_descriptors(commands, extension_op_names) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match validate_app_command_framework_dependencies(commands) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  Ok(())
}

///|
fn validate_app_command_framework_dependencies(
  commands : AppCommandsConfig,
) -> Result[Unit, String] {
  let ids : Map[String, Bool] = {}
  for id in commands.framework_extension_ids() {
    guard id.trim().to_owned() != "" else {
      return Err("command framework dependency id must not be empty")
    }
    guard ids.get(id) is None else {
      return Err("duplicate command framework dependency: " + id)
    }
    ids[id] = true
  }
  Ok(())
}

///|
fn validate_app_command_descriptor(
  descriptor : @ipc.IpcExtensionDescriptor,
  op_names : Map[String, Bool],
  extension_ids : Map[String, Bool],
  extension_namespaces : Map[String, Bool],
  extension_op_names : Map[String, Bool],
) -> Result[Unit, String] {
  guard descriptor.id.trim().to_owned() != "" else {
    return Err("command extension descriptor id must not be empty")
  }
  guard extension_ids.get(descriptor.id) is None else {
    return Err("duplicate command extension descriptor id: " + descriptor.id)
  }
  extension_ids[descriptor.id] = true
  guard descriptor.js_namespace.trim().to_owned() != "" else {
    return Err(
      "command extension descriptor namespace must not be empty: " +
      descriptor.id,
    )
  }
  guard descriptor.js_namespace.find("/") is None else {
    return Err(
      "command extension descriptor namespace must not contain '/': " +
      descriptor.js_namespace,
    )
  }
  guard !app_command_js_property_is_reserved(descriptor.js_namespace) else {
    return Err(
      "command extension descriptor namespace is reserved: " +
      descriptor.js_namespace,
    )
  }
  guard extension_namespaces.get(descriptor.js_namespace) is None else {
    return Err(
      "duplicate command extension descriptor namespace: " +
      descriptor.js_namespace,
    )
  }
  extension_namespaces[descriptor.js_namespace] = true
  validate_ipc_descriptor_apis(descriptor, op_names, extension_op_names)
}

///|
fn validate_ipc_descriptor_apis(
  descriptor : @ipc.IpcExtensionDescriptor,
  op_names : Map[String, Bool],
  extension_op_names : Map[String, Bool],
) -> Result[Unit, String] {
  guard descriptor.apis.length() > 0 else {
    return Err(
      "command extension descriptor must expose at least one API: " +
      descriptor.id,
    )
  }
  let api_names : Map[String, Bool] = {}
  for api in descriptor.apis {
    guard api.api_name.trim().to_owned() != "" else {
      return Err(
        "command extension descriptor API name must not be empty: " +
        descriptor.id,
      )
    }
    guard api.api_name.find("/") is None else {
      return Err(
        "command extension descriptor API name must not contain '/': " +
        descriptor.id +
        "." +
        api.api_name,
      )
    }
    guard !app_command_js_property_is_reserved(api.api_name) else {
      return Err(
        "command extension descriptor API name is reserved: " +
        descriptor.id +
        "." +
        api.api_name,
      )
    }
    guard api_names.get(api.api_name) is None else {
      return Err(
        "duplicate command extension descriptor API: " +
        descriptor.id +
        "." +
        api.api_name,
      )
    }
    api_names[api.api_name] = true
    let op_name = app_command_extension_op_name(
      descriptor.js_namespace,
      api.api_name,
    )
    guard op_names.get(op_name) is Some(_) else {
      return Err("command extension descriptor API is missing op: " + op_name)
    }
    extension_op_names[op_name] = true
  }
  Ok(())
}

///|
fn validate_extension_op_names_have_descriptors(
  commands : AppCommandsConfig,
  extension_op_names : Map[String, Bool],
) -> Result[Unit, String] {
  for op_name in commands.op_names() {
    if op_name.has_prefix("ext:") && extension_op_names.get(op_name) is None {
      return Err("command extension op is missing descriptor: " + op_name)
    }
  }
  Ok(())
}

///|
fn validate_framework_manifest_extensions(
  manifest : @manifest.AppManifest,
  registry : ExtensionRegistry,
  commands : AppCommandsConfig,
) -> Result[Unit, String] {
  match validate_app_commands_config(commands) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let framework_specs = registry.spec_map()
  let command_extension_ids = command_extension_id_map(commands.extensions())
  for id, _present in command_extension_ids {
    guard framework_specs.get(id) is None else {
      return Err(
        "command extension id collides with framework extension id: " + id,
      )
    }
  }
  for entry in manifest.extension_settings() {
    let (id, _setting) = entry
    guard framework_specs.get(id) is Some(_) ||
      command_extension_ids.get(id) is Some(_) else {
      return Err("unknown framework or command extension key: " + id)
    }
  }
  for id in commands.framework_extension_ids() {
    guard framework_specs.get(id) is Some(_) else {
      return Err("unknown command framework dependency: " + id)
    }
    match manifest.extension_setting(id) {
      Some(@manifest.ExtensionSetting::Disabled) =>
        return Err(
          "command extension requires disabled framework dependency " + id,
        )
      _ => ()
    }
  }
  match
    validate_framework_command_namespaces_do_not_collide(
      manifest, registry, commands,
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  Ok(())
}

///|
fn validate_framework_command_namespaces_do_not_collide(
  manifest : @manifest.AppManifest,
  registry : ExtensionRegistry,
  commands : AppCommandsConfig,
) -> Result[Unit, String] {
  let command_namespaces = command_extension_namespace_map(
    commands.extensions(),
  )
  let framework_manifest = framework_manifest_for_commands(
    manifest, registry, commands,
  )
  let prepared = match plan_extensions(framework_manifest, registry) {
    Ok(prepared) => prepared
    Err(error) => return Err(error)
  }
  for extension in prepared {
    let spec = extension.spec()
    match command_namespaces.get(spec.js_namespace()) {
      Some(command_id) =>
        return Err(
          "command extension namespace collides with framework extension namespace: " +
          command_id +
          " -> " +
          spec.js_namespace(),
        )
      None => ()
    }
  }
  Ok(())
}

///|
fn framework_manifest_for_commands(
  manifest : @manifest.AppManifest,
  registry : ExtensionRegistry,
  commands : AppCommandsConfig,
) -> @manifest.AppManifest {
  @manifest.AppManifest::new(
    manifest.window,
    manifest.entry,
    debug=manifest.debug,
    windows=manifest.windows,
    extensions=framework_extension_settings(manifest, registry, commands),
  )
}

///|
fn framework_extension_settings(
  manifest : @manifest.AppManifest,
  registry : ExtensionRegistry,
  commands : AppCommandsConfig,
) -> Map[String, @manifest.ExtensionSetting] {
  let specs = registry.spec_map()
  let settings : Map[String, @manifest.ExtensionSetting] = {}
  for entry in manifest.extension_settings() {
    let (id, setting) = entry
    if specs.get(id) is Some(_) {
      settings[id] = setting
    }
  }
  for id in commands.framework_extension_ids() {
    if specs.get(id) is Some(_) && settings.get(id) is None {
      settings[id] = @manifest.ExtensionSetting::enabled()
    }
  }
  settings
}

///|
fn command_extension_id_map(
  descriptors : Array[@ipc.IpcExtensionDescriptor],
) -> Map[String, Bool] {
  let ids : Map[String, Bool] = {}
  for descriptor in descriptors {
    ids[descriptor.id] = true
  }
  ids
}

///|
fn command_extension_namespace_map(
  descriptors : Array[@ipc.IpcExtensionDescriptor],
) -> Map[String, String] {
  let namespaces : Map[String, String] = {}
  for descriptor in descriptors {
    namespaces[descriptor.js_namespace] = descriptor.id
  }
  namespaces
}

///|
fn write_framework_process_ipc_config(
  path : String,
  manifest : @manifest.AppManifest,
  ipc_config : FrameworkIpcLaunchConfig,
  commands : AppCommandsConfig,
  base_dir? : String? = None,
  extension_registry? : ExtensionRegistry = ExtensionRegistry::new(),
) -> Result[Unit, String] {
  match validate_app_commands_config(commands) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match
    validate_framework_manifest_extensions(
      manifest, extension_registry, commands,
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let config = FrameworkProcessConfig::{
    version: framework_config_version,
    manifest: @bootstrap.app_manifest_to_json(manifest),
    base_dir,
    ipc: Some(framework_ipc_launch_config_ws(ipc_config)),
    op_names: commands.op_names(),
    extensions: commands.extensions(),
    framework_extension_ids: commands.framework_extension_ids(),
  }
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  try {
    @mbfs.write_string_to_file(
      path,
      ToJson::to_json(config).stringify(indent=2),
    )
    Ok(())
  } catch {
    err => Err(@debug.render(@debug.to_repr(err)))
  }
}

///|
fn default_framework_process_config_path(
  ipc_config : FrameworkIpcLaunchConfig,
) -> String {
  let ws = framework_ipc_launch_config_ws(ipc_config)
  "target/lepus-framework-" + ws.token + ".json"
}

///|
fn framework_launch_args(
  framework_args : Array[String],
  config_path : String,
) -> Array[String] {
  let args = framework_args.copy()
  args.push(framework_config_arg_name)
  args.push(config_path)
  args
}

///|
fn validate_framework_process_config(
  config : FrameworkProcessConfig,
) -> Result[Unit, String] {
  guard config.version == framework_config_version else {
    return Err(
      "unsupported framework config version: " + config.version.to_string(),
    )
  }
  guard config.manifest is Object(_) else {
    return Err("framework config manifest must be an object")
  }
  guard config.ipc is Some(_) else {
    return Err("framework config ipc must be present")
  }
  match
    validate_app_commands_config(
      app_commands_config_from_framework_config(config),
    ) {
    Err(error) => Err("invalid framework config commands: " + error)
    Ok(_) => Ok(())
  }
}

///|
fn app_commands_config_from_framework_config(
  config : FrameworkProcessConfig,
) -> AppCommandsConfig {
  AppCommandsConfig::from_ipc_descriptors(
    config.op_names,
    config.extensions,
    config.framework_extension_ids,
  )
}

///|
fn read_framework_config(
  path : String,
) -> Result[FrameworkProcessConfig, String] {
  let text = Ok(@mbfs.read_file_to_string(path)) catch {
    err => Err(@debug.render(@debug.to_repr(err)))
  }
  text.bind(fn(text) {
    let parsed : Result[Json, _] = try? @json.parse(text)
    parsed
    .map_err(fn(err) { err.to_string() })
    .bind(fn(json) {
      let config : Result[FrameworkProcessConfig, _] = try? @json.from_json(
        json,
      )
      config.map_err(fn(err) { err.to_string() })
    })
  })
}

///|
fn framework_config_path_from_env_or_args() -> Result[String, String] {
  framework_config_path(
    @sys.get_cli_args(),
    @sys.get_env_var(framework_config_env_name),
  )
}

///|
fn framework_config_path_from_args(
  args : Array[String],
) -> Result[String?, String] {
  let mut index = 0
  let mut matched : String? = None
  while index < args.length() {
    if args[index] == framework_config_arg_name {
      guard index + 1 < args.length() else {
        return Err("missing value for " + framework_config_arg_name)
      }
      guard matched is None else {
        return Err("duplicate value for " + framework_config_arg_name)
      }
      matched = Some(args[index + 1])
      index = index + 2
    } else {
      index = index + 1
    }
  }
  Ok(matched)
}

///|
fn framework_config_path(
  args : Array[String],
  env_path : String?,
) -> Result[String, String] {
  match framework_config_path_from_args(args) {
    Err(error) => Err(error)
    Ok(Some(path)) => validate_framework_config_path(path)
    Ok(None) =>
      match env_path {
        Some(path) if path != "" => validate_framework_config_path(path)
        _ => Err(missing_framework_config_message())
      }
  }
}

///|
fn validate_framework_config_path(path : String) -> Result[String, String] {
  guard path.trim().to_owned() != "" else {
    return Err("framework config path must not be empty")
  }
  Ok(path)
}

///|
fn missing_framework_config_message() -> String {
  "missing framework config; pass " +
  framework_config_arg_name +
  " or set " +
  framework_config_env_name
}
