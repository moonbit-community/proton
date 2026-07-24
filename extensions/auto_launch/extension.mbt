///|
struct EmptyPayload {} derive(ToJson, FromJson, Debug, Eq)

///|
/// Returns platform support details for JavaScript callers.
#proton.command(name="support")
fn support(_payload : EmptyPayload?) -> SupportReply {
  auto_launch_support()
}

///|
/// Describes the resolved native startup entry.
#proton.command(name="describe")
fn describe(
  name : String,
  path : String?,
  launch_in_background : Bool?,
  background_arg : String?,
  extra_arguments : Array[String]?,
  identifier : String?,
) -> AutoLaunchReply raise AutoLaunchError {
  describe_auto_launch(
    auto_launch_payload(
      name, path, launch_in_background, background_arg, extra_arguments, identifier,
    ),
  )
}

///|
/// Returns whether the resolved native startup entry is enabled.
#proton.command(name="isEnabled")
fn is_enabled(
  name : String,
  path : String?,
  launch_in_background : Bool?,
  background_arg : String?,
  extra_arguments : Array[String]?,
  identifier : String?,
) -> EnabledReply raise AutoLaunchError {
  is_auto_launch_enabled(
    auto_launch_payload(
      name, path, launch_in_background, background_arg, extra_arguments, identifier,
    ),
  )
}

///|
/// Enables the resolved native startup entry.
#proton.command(name="enable")
async fn enable(
  context : @proton_command.AppCommandExtensionContext,
  name : String,
  path : String?,
  launch_in_background : Bool?,
  background_arg : String?,
  extra_arguments : Array[String]?,
  identifier : String?,
) -> MutationReply raise AutoLaunchError {
  let identifier = enable_auto_launch(
    auto_launch_payload(
      name, path, launch_in_background, background_arg, extra_arguments, identifier,
    ),
  )
  emit_auto_launch_activity(context, AutoLaunchActivity::{
    operation: "enable",
    identifier: Some(identifier),
  })
  MutationReply::{ changed: true }
}

///|
/// Disables the resolved native startup entry.
#proton.command(name="disable")
async fn disable(
  context : @proton_command.AppCommandExtensionContext,
  name : String,
  path : String?,
  launch_in_background : Bool?,
  background_arg : String?,
  extra_arguments : Array[String]?,
  identifier : String?,
) -> MutationReply raise AutoLaunchError {
  let identifier = disable_auto_launch(
    auto_launch_payload(
      name, path, launch_in_background, background_arg, extra_arguments, identifier,
    ),
  )
  emit_auto_launch_activity(context, AutoLaunchActivity::{
    operation: "disable",
    identifier: Some(identifier),
  })
  MutationReply::{ changed: true }
}

///|
#proton.event(name="activity")
struct AutoLaunchActivity {
  operation : String
  identifier : String?
} derive(ToJson, FromJson, Debug, Eq)
