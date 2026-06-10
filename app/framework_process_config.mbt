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
    try @json.parse(text) catch {
      err => Err(err.to_string())
    } noraise {
      json =>
        try @json.from_json(json) catch {
          err => Err(err.to_string())
        } noraise {
          config => Ok(config)
        }
    }
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
