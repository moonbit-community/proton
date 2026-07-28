///|
let support_command = @auto_launch_contract.support

///|
let describe_command = @auto_launch_contract.describe

///|
let is_enabled_command = @auto_launch_contract.is_enabled

///|
let enable_command = @auto_launch_contract.enable

///|
let disable_command = @auto_launch_contract.disable

///|
/// Returns platform support details for JavaScript callers.
#proton.command(contract=support_command)
fn support(
  _request : @auto_launch_contract.SupportRequest,
) -> @auto_launch_contract.SupportReply {
  auto_launch_support()
}

///|
/// Describes the resolved native startup entry.
#proton.command(contract=describe_command)
fn describe(
  request : @auto_launch_contract.AutoLaunchRequest,
) -> @auto_launch_contract.AutoLaunchReply raise AutoLaunchError {
  describe_auto_launch(request)
}

///|
/// Returns whether the resolved native startup entry is enabled.
#proton.command(contract=is_enabled_command)
fn is_enabled(
  request : @auto_launch_contract.AutoLaunchRequest,
) -> @auto_launch_contract.EnabledReply raise AutoLaunchError {
  is_auto_launch_enabled(request)
}

///|
/// Enables the resolved native startup entry.
#proton.command(contract=enable_command)
async fn enable(
  context : @proton.CommandContext,
  request : @auto_launch_contract.AutoLaunchRequest,
) -> @auto_launch_contract.MutationReply {
  let identifier = enable_auto_launch(request)
  context.emit(@auto_launch_contract.activity, @auto_launch_contract.AutoLaunchActivity::{
    operation: "enable",
    identifier: Some(identifier),
  })
  @auto_launch_contract.MutationReply::{ changed: true }
}

///|
/// Disables the resolved native startup entry.
#proton.command(contract=disable_command)
async fn disable(
  context : @proton.CommandContext,
  request : @auto_launch_contract.AutoLaunchRequest,
) -> @auto_launch_contract.MutationReply {
  let identifier = disable_auto_launch(request)
  context.emit(@auto_launch_contract.activity, @auto_launch_contract.AutoLaunchActivity::{
    operation: "disable",
    identifier: Some(identifier),
  })
  @auto_launch_contract.MutationReply::{ changed: true }
}

///|
pub fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    generated_extension_contract,
    generated_extension_command_routes(),
    fn(_context, registrar) raise { register_commands(registrar) },
  )
}
