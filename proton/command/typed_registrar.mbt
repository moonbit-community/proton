///|
/// Request-scoped context supplied to typed application command handlers.
///
/// Lifecycle-owned task and event capabilities are added by the application
/// runner; the registrar keeps handlers independent from transport details.
pub type CommandContext = @core.AppCommandRequestContext

///|
pub type CommandWindow = @core.CommandWindow

///|
/// Startup-only capability for binding typed command descriptors to handlers.
pub struct CommandRegistrar {
  host : @core.AppCommandHost
  owner : (String, String)?
  routes : Array[@proton_contract.ContractRoute]
  mut registration_closed : Bool
}

///|
/// Creates a registrar over one application command host.
#doc(hidden)
pub fn CommandRegistrar::CommandRegistrar(
  host : @core.AppCommandHost,
) -> CommandRegistrar {
  CommandRegistrar::{
    host,
    owner: None,
    routes: [],
    registration_closed: false,
  }
}

///|
/// Binds one typed descriptor to an asynchronous command handler.
///
/// Request decoding and response encoding are selected from the descriptor's
/// type parameters. The descriptor is the only source of command identity.
pub fn[Request : @json.FromJson, Response : ToJson] CommandRegistrar::bind(
  self : CommandRegistrar,
  command : @proton_contract.Command[Request, Response],
  handler : async (CommandContext, Request) -> Response,
) -> Unit raise {
  guard !self.registration_closed else {
    raise @core.OpRegistrationError::RegistrationSealed
  }
  command.validate()
  let route = command.contract_route()
  if self.owner is Some((id, js_namespace)) {
    guard route.extension_id() == Some(id) &&
      route.extension_namespace() == Some(js_namespace) else {
      raise ExtensionSpecError::ForeignCommandRoute(
        extension_id=id,
        operation_name=route.operation_name(),
      )
    }
  }
  self.host.op_async_with_context(route.operation_name(), handler)
  self.routes.push(route)
}
