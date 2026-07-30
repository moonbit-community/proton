///|
/// Request-scoped context supplied to typed application command handlers.
///
/// Lifecycle-owned task and event capabilities are added by the application
/// runner; the registrar keeps handlers independent from transport details.
pub type CommandContext = @core.AppCommandRequestContext

///|
/// Startup-only capability for binding typed command descriptors to handlers.
pub struct CommandRegistrar {
  host : @core.AppCommandHost
}

///|
/// Creates a registrar over one application command host.
#doc(hidden)
pub fn CommandRegistrar::new(host : @core.AppCommandHost) -> CommandRegistrar {
  CommandRegistrar::{ host, }
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
  command.validate()
  self.host.op_async_with_context(
    command.contract_route().operation_name(),
    handler,
  )
}
