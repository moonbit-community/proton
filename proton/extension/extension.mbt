///|
priv enum ExtensionKind {
  Framework(@core.ExtensionSpec)
  Command(@proton_command.AppCommandExtensionSpec)
}

///|
struct Extension {
  kind : ExtensionKind
}

///|
struct Extensions {
  items : Array[Extension]
}

///|
priv struct CoreCommandDescriptor {
  apis : Array[@proton_command.AppCommandApiDescriptor]
  scripts : Array[String]
}

///|
pub fn from_core_spec(spec : @core.ExtensionSpec) -> Extension {
  Extension::{ kind: Framework(spec) }
}

///|
pub fn from_command_spec(
  spec : @proton_command.AppCommandExtensionSpec,
) -> Extension {
  Extension::{ kind: Command(spec) }
}

///|
pub fn Extensions::new(items : Array[Extension]) -> Extensions {
  Extensions::{ items: copy_extensions(items) }
}

///|
pub fn extensions(items : Array[Extension]) -> Extensions {
  Extensions::new(items)
}

///|
pub fn Extension::id(self : Extension) -> String {
  match self.kind {
    Framework(spec) => spec.id()
    Command(spec) => spec.id()
  }
}

///|
pub fn Extension::core_spec(self : Extension) -> @core.ExtensionSpec? {
  match self.kind {
    Framework(spec) => Some(spec)
    Command(_) => None
  }
}

///|
pub fn Extension::command_spec(
  self : Extension,
) -> @proton_command.AppCommandExtensionSpec? {
  match self.kind {
    Framework(spec) => core_command_spec(spec)
    Command(spec) => Some(spec)
  }
}

///|
pub fn Extensions::items(self : Extensions) -> Array[Extension] {
  copy_extensions(self.items)
}

///|
fn copy_extensions(items : Array[Extension]) -> Array[Extension] {
  items.map(fn(item) { item })
}

///|
fn core_command_spec(
  spec : @core.ExtensionSpec,
) -> @proton_command.AppCommandExtensionSpec? {
  match core_command_descriptor(spec) {
    Err(_) => None
    Ok(descriptor) =>
      Some(
        @proton_command.AppCommandExtensionSpec::new(
          spec.id(),
          spec.js_namespace(),
          descriptor.apis,
          fn(context) { register_core_commands(spec, context) },
          scripts=descriptor.scripts,
          dependencies=spec.dependencies(),
        ),
      )
  }
}

///|
fn core_command_descriptor(
  spec : @core.ExtensionSpec,
) -> Result[CoreCommandDescriptor, String] {
  let core_host = @core.ExtensionHost::new()
  match spec.build_default() {
    Err(error) => Err(error)
    Ok(extension) => {
      let scripts = extension.scripts()
      core_host.install(extension)
      let apis = core_host
        .api_names(spec.js_namespace())
        .map(fn(api_name) {
          @proton_command.AppCommandApiDescriptor::new(api_name)
        })
      core_host.destroy()
      Ok(CoreCommandDescriptor::{ apis, scripts })
    }
  }
}

///|
fn register_core_commands(
  spec : @core.ExtensionSpec,
  context : @proton_command.AppCommandExtensionContext,
) -> Result[Unit, String] {
  let core_context = @core.ExtensionBuildContext::new(
    options=context.options(),
    base_dir=context.base_dir(),
  )
  match spec.build_extension(core_context) {
    Err(error) => Err(error)
    Ok(extension) => {
      let core_host = @core.ExtensionHost::new()
      core_host.install(extension)
      for api_name in core_host.api_names(spec.js_namespace()) {
        let op_name = context.op_name(api_name)
        context.op_result(api_name, fn(payload : Json) {
          core_host.dispatch_op(op_name, payload)
        })
      }
      Ok(())
    }
  }
}
