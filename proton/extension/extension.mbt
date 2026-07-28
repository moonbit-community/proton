///|
priv enum ExtensionKind {
  Framework(@core.ExtensionSpec)
  Command(@proton_command.AppCommandExtensionSpec)
  Typed(TypedExtensionSpec)
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
priv struct TypedExtensionSpec {
  contract : @proton_contract.ExtensionContract
  command_routes : Array[@proton_contract.ContractRoute]
  register : (
    @proton_command.AppCommandExtensionContext,
    @proton_command.CommandRegistrar,
  ) -> Unit raise
  scripts : Array[String]
  dependencies : Array[String]
  on_destroy : (@proton_command.AppCommandExtensionContext) -> Unit raise
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
/// Builds an installable extension from typed command descriptors.
///
/// Validation is deferred until application configuration so invalid static
/// extension metadata follows the facade's ordinary adaptation error path.
pub fn typed(
  contract : @proton_contract.ExtensionContract,
  command_routes : Array[@proton_contract.ContractRoute],
  register : (
    @proton_command.AppCommandExtensionContext,
    @proton_command.CommandRegistrar,
  ) -> Unit raise,
  scripts? : Array[String] = [],
  dependencies? : Array[String] = [],
  on_destroy? : (@proton_command.AppCommandExtensionContext) -> Unit raise = fn(
    _context,
  ) {

  },
) -> Extension {
  Extension::{
    kind: Typed(TypedExtensionSpec::{
      contract,
      command_routes: command_routes.map(route => route),
      register,
      scripts: scripts.map(script => script),
      dependencies: dependencies.map(dependency => dependency),
      on_destroy,
    }),
  }
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
    Typed(spec) => spec.contract.id()
  }
}

///|
pub fn Extension::core_spec(self : Extension) -> @core.ExtensionSpec? {
  match self.kind {
    Framework(spec) => Some(spec)
    Command(_) | Typed(_) => None
  }
}

///|
pub fn Extension::command_spec(
  self : Extension,
) -> @proton_command.AppCommandExtensionSpec? raise ExtensionAdapterError {
  match self.kind {
    Framework(spec) => Some(core_command_spec(spec))
    Command(spec) => Some(spec)
    Typed(spec) =>
      Some(
        @proton_command.AppCommandExtensionSpec::typed(
          spec.contract,
          spec.command_routes,
          spec.register,
          scripts=spec.scripts,
          dependencies=spec.dependencies,
          on_destroy=spec.on_destroy,
        ) catch {
          error =>
            raise TypedSpecInvalid(
              extension_id=spec.contract.id(),
              detail=error.message(),
            )
        },
      )
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
) -> @proton_command.AppCommandExtensionSpec raise ExtensionAdapterError {
  let descriptor = core_command_descriptor(spec)
  let core_host_ref : Ref[@core.ExtensionHost?] = Ref(None)
  @proton_command.AppCommandExtensionSpec::new(
    spec.id(),
    spec.js_namespace(),
    descriptor.apis,
    fn(context) raise { register_core_commands(spec, context, core_host_ref) },
    scripts=descriptor.scripts,
    dependencies=spec.dependencies(),
    on_destroy=fn(_context) raise { destroy_core_command_host(core_host_ref) },
  )
}

///|
fn core_command_descriptor(
  spec : @core.ExtensionSpec,
) -> CoreCommandDescriptor raise ExtensionAdapterError {
  let core_host = @core.ExtensionHost::new()
  let extension = spec.build_default() catch {
    error =>
      raise DescriptorBuildFailed(
        extension_id=spec.id(),
        detail=@debug.render(Repr(error)),
      )
  }
  let scripts = extension.scripts()
  core_host.install(extension) catch {
    error => {
      core_host.destroy() catch {
        _ => ()
      }
      raise DescriptorInstallFailed(
        extension_id=spec.id(),
        detail=@debug.render(Repr(error)),
      )
    }
  }
  let apis = core_host
    .api_names(spec.js_namespace())
    .map(fn(api_name) { @proton_command.AppCommandApiDescriptor::new(api_name) })
  core_host.destroy() catch {
    error =>
      raise DescriptorInstallFailed(
        extension_id=spec.id(),
        detail=@debug.render(Repr(error)),
      )
  }
  CoreCommandDescriptor::{ apis, scripts }
}

///|
fn register_core_commands(
  spec : @core.ExtensionSpec,
  context : @proton_command.AppCommandExtensionContext,
  core_host_ref : Ref[@core.ExtensionHost?],
) -> Unit raise {
  destroy_core_command_host(core_host_ref)
  let core_context = @core.ExtensionBuildContext::new(
    options=context.options(),
    base_dir=context.base_dir(),
  )
  let extension = spec.build_extension(core_context)
  let core_host = @core.ExtensionHost::new()
  core_host.install(extension)
  for api_name in core_host.api_names(spec.js_namespace()) {
    let op_name = context.op_name(api_name)
    context.op(api_name, fn(payload : Json) raise {
      core_host.dispatch_op(op_name, payload)
    })
  }
  core_host_ref.val = Some(core_host)
}

///|
fn destroy_core_command_host(
  core_host_ref : Ref[@core.ExtensionHost?],
) -> Unit raise {
  match core_host_ref.val {
    Some(core_host) => {
      core_host.destroy()
      core_host_ref.val = None
    }
    None => ()
  }
}
