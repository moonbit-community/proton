///|
priv struct PreparedAppCommandExtension {
  id : String
  spec : @proton_command.AppCommandExtensionSpec
  options : Json?
}

///|
/// Runs manifest-enabled command extensions in this user process and starts a
/// framework/webview child process.
///
/// This is the preferred multi-process entrypoint for apps. User code remains
/// the parent process; the framework child reads a generated config and
/// connects back to the local IPC server.
async fn run_app_command_extensions_with_framework_process(
  manifest : @manifest.AppManifest,
  framework_command : String,
  registry : @proton_command.AppCommandExtensionRegistry,
  extension_registry? : ExtensionRegistry = ExtensionRegistry::new(),
  framework_args? : Array[String] = [],
  framework_cwd? : String? = None,
  base_dir? : String? = None,
  ipc_token? : String? = None,
  framework_config_path? : String? = None,
) -> Result[Unit, String] {
  let prepared = match
    plan_app_command_extensions(manifest, registry, extension_registry~) {
    Err(error) => return Err(error)
    Ok(prepared) => prepared
  }
  guard prepared.length() > 0 else {
    return Err("app command extension registry did not enable any extension")
  }
  let host = @core.AppCommandHost::new()
  let registered : Array[
    (
      @proton_command.AppCommandExtensionSpec,
      @proton_command.AppCommandExtensionContext,
    ),
  ] = []
  for extension in prepared {
    let spec = extension.spec()
    let context = @proton_command.AppCommandExtensionContext::new(
      host,
      extension.id(),
      spec.js_namespace(),
      options=extension.options(),
      base_dir~,
    )
    match spec.register(context) {
      Err(error) => {
        destroy_registered_command_extensions(registered)
        host.close()
        return Err(
          "failed to register command extension " + spec.id() + ": " + error,
        )
      }
      Ok(_) => registered.push((spec, context))
    }
  }
  match validate_registered_command_extension_handlers(prepared, host) {
    Err(error) => {
      destroy_registered_command_extensions(registered)
      host.close()
      return Err(error)
    }
    Ok(_) => ()
  }
  let result = run_app_command_host_with_framework_process(
    manifest,
    framework_command,
    host,
    app_commands_config_from_prepared(prepared, extension_registry.spec_map()),
    extension_registry~,
    framework_args~,
    framework_cwd~,
    base_dir~,
    ipc_token~,
    framework_config_path~,
  )
  destroy_registered_command_extensions(registered)
  host.close()
  result
}

///|
fn destroy_registered_command_extensions(
  registered : Array[
    (
      @proton_command.AppCommandExtensionSpec,
      @proton_command.AppCommandExtensionContext,
    ),
  ],
) -> Unit {
  for i = registered.length(); i > 0; {
    let entry = registered[i - 1]
    entry.0.destroy(entry.1)
    continue i - 1
  }
}

///|
fn app_commands_config_from_prepared(
  prepared : Array[PreparedAppCommandExtension],
  framework_specs_by_id : Map[String, @core.ExtensionSpec],
) -> @proton_command.AppCommandsConfig {
  let op_names : Array[String] = []
  let descriptors : Array[@ipc.IpcExtensionDescriptor] = []
  let framework_extension_ids : Array[String] = []
  let seen_framework_extension_ids : Map[String, Bool] = {}
  for extension in prepared {
    let spec = extension.spec()
    for op_name in spec.op_names() {
      op_names.push(op_name)
    }
    for dependency in spec.dependencies() {
      if framework_specs_by_id.get(dependency) is Some(_) &&
        seen_framework_extension_ids.get(dependency) is None {
        seen_framework_extension_ids[dependency] = true
        framework_extension_ids.push(dependency)
      }
    }
    descriptors.push(spec.to_ipc_descriptor())
  }
  @proton_command.AppCommandsConfig::from_ipc_descriptors(
    op_names, descriptors, framework_extension_ids,
  )
}

///|
fn validate_command_extension_registry(
  registry : @proton_command.AppCommandExtensionRegistry,
) -> Result[Unit, String] {
  let namespaces : Map[String, String] = {}
  let op_names : Map[String, String] = {}
  for id in registry.ordered_names() {
    let spec = match registry.spec_map().get(id) {
      Some(spec) => spec
      None => return Err("missing command extension spec: " + id)
    }
    match validate_command_extension_spec_shape(spec) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match namespaces.get(spec.js_namespace()) {
      Some(existing_id) =>
        return Err(
          "command extension " +
          spec.id() +
          " reuses namespace " +
          spec.js_namespace() +
          " from " +
          existing_id,
        )
      None => namespaces[spec.js_namespace()] = spec.id()
    }
    for api in spec.apis() {
      let op_name = @proton_command.app_command_extension_op_name(
        spec.js_namespace(),
        api.api_name(),
      )
      match op_names.get(op_name) {
        Some(existing_id) =>
          return Err(
            "command extension " +
            spec.id() +
            " reuses op " +
            op_name +
            " from " +
            existing_id,
          )
        None => op_names[op_name] = spec.id()
      }
    }
  }
  Ok(())
}

///|
fn validate_command_extension_spec_shape(
  spec : @proton_command.AppCommandExtensionSpec,
) -> Result[Unit, String] {
  guard spec.id().trim().to_owned() != "" else {
    return Err("command extension id must not be empty")
  }
  guard spec.js_namespace().trim().to_owned() != "" else {
    return Err("command extension namespace must not be empty: " + spec.id())
  }
  guard spec.js_namespace().find("/") is None else {
    return Err(
      "command extension namespace must not contain '/': " + spec.js_namespace(),
    )
  }
  guard !@proton_command.app_command_js_property_is_reserved(
    spec.js_namespace(),
  ) else {
    return Err(
      "command extension namespace is reserved: " + spec.js_namespace(),
    )
  }
  match validate_command_api_descriptors(spec.id(), spec.apis()) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  validate_command_extension_dependencies(spec.id(), spec.dependencies())
}

///|
fn validate_command_api_descriptors(
  owner_id : String,
  apis : Array[@proton_command.AppCommandApiDescriptor],
) -> Result[Unit, String] {
  guard apis.length() > 0 else {
    return Err("command extension must expose at least one API: " + owner_id)
  }
  let api_names : Map[String, Bool] = {}
  for api in apis {
    let api_name = api.api_name()
    guard api_name.trim().to_owned() != "" else {
      return Err("command extension API name must not be empty: " + owner_id)
    }
    guard api_name.find("/") is None else {
      return Err(
        "command extension API name must not contain '/': " +
        owner_id +
        "." +
        api_name,
      )
    }
    guard !@proton_command.app_command_js_property_is_reserved(api_name) else {
      return Err(
        "command extension API name is reserved: " + owner_id + "." + api_name,
      )
    }
    guard api_names.get(api_name) is None else {
      return Err(
        "duplicate command extension API: " + owner_id + "." + api_name,
      )
    }
    api_names[api_name] = true
  }
  Ok(())
}

///|
fn validate_command_extension_dependencies(
  owner_id : String,
  dependencies : Array[String],
) -> Result[Unit, String] {
  let seen : Map[String, Bool] = {}
  for dependency in dependencies {
    guard dependency.trim().to_owned() != "" else {
      return Err("command extension dependency must not be empty: " + owner_id)
    }
    guard dependency != owner_id else {
      return Err("command extension must not depend on itself: " + owner_id)
    }
    guard seen.get(dependency) is None else {
      return Err(
        "duplicate command extension dependency: " +
        owner_id +
        " -> " +
        dependency,
      )
    }
    seen[dependency] = true
  }
  Ok(())
}

///|
fn validate_registered_command_extension_handlers(
  prepared : Array[PreparedAppCommandExtension],
  host : @core.AppCommandHost,
) -> Result[Unit, String] {
  let registered : Map[String, Bool] = {}
  for op_name in host.registered_ops() {
    registered[op_name] = true
  }
  let expected : Map[String, Bool] = {}
  for extension in prepared {
    let spec = extension.spec()
    for op_name in spec.op_names() {
      expected[op_name] = true
      guard registered.get(op_name) is Some(_) else {
        return Err(
          "command extension " +
          spec.id() +
          " did not register handler for " +
          op_name,
        )
      }
    }
  }
  for op_name in host.registered_ops() {
    guard expected.get(op_name) is Some(_) else {
      return Err("command extension registered undeclared handler: " + op_name)
    }
  }
  Ok(())
}

///|
fn PreparedAppCommandExtension::new(
  id : String,
  spec : @proton_command.AppCommandExtensionSpec,
  options : Json?,
) -> PreparedAppCommandExtension {
  PreparedAppCommandExtension::{
    id,
    spec: copy_app_command_extension_spec(spec),
    options: clone_json_option(options),
  }
}

///|
fn PreparedAppCommandExtension::id(
  self : PreparedAppCommandExtension,
) -> String {
  self.id
}

///|
fn PreparedAppCommandExtension::spec(
  self : PreparedAppCommandExtension,
) -> @proton_command.AppCommandExtensionSpec {
  copy_app_command_extension_spec(self.spec)
}

///|
fn PreparedAppCommandExtension::options(
  self : PreparedAppCommandExtension,
) -> Json? {
  clone_json_option(self.options)
}

///|
fn copy_app_command_extension_spec(
  spec : @proton_command.AppCommandExtensionSpec,
) -> @proton_command.AppCommandExtensionSpec {
  @proton_command.AppCommandExtensionSpec::new(
    spec.id,
    spec.js_namespace,
    spec.apis,
    spec.register,
    scripts=spec.scripts,
    dependencies=spec.dependencies,
    on_destroy=spec.on_destroy,
  )
}
