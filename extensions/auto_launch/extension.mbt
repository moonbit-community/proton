///|
struct EmptyPayload {} derive(ToJson, FromJson, Debug, Eq)

///|
/// Returns platform support details for JavaScript callers.
#lepus.command(name="support")
fn support(_payload : EmptyPayload?) -> SupportReply {
  auto_launch_support()
}

///|
/// Describes the resolved native startup entry.
#lepus.command(name="describe")
fn describe(
  name : String,
  path : String?,
  launch_in_background : Bool?,
  background_arg : String?,
  extra_arguments : Array[String]?,
  identifier : String?,
) -> Result[AutoLaunchReply, String] {
  describe_auto_launch(
    auto_launch_payload(
      name, path, launch_in_background, background_arg, extra_arguments, identifier,
    ),
  )
}

///|
/// Returns whether the resolved native startup entry is enabled.
#lepus.command(name="isEnabled")
fn is_enabled(
  name : String,
  path : String?,
  launch_in_background : Bool?,
  background_arg : String?,
  extra_arguments : Array[String]?,
  identifier : String?,
) -> Result[EnabledReply, String] {
  is_auto_launch_enabled(
    auto_launch_payload(
      name, path, launch_in_background, background_arg, extra_arguments, identifier,
    ),
  )
}

///|
/// Enables the resolved native startup entry.
#lepus.command(name="enable")
async fn enable(
  context : @lepus.AppCommandExtensionContext,
  name : String,
  path : String?,
  launch_in_background : Bool?,
  background_arg : String?,
  extra_arguments : Array[String]?,
  identifier : String?,
) -> Result[MutationReply, String] {
  match
    enable_auto_launch(
      auto_launch_payload(
        name, path, launch_in_background, background_arg, extra_arguments, identifier,
      ),
    ) {
    Err(error) => Err(error)
    Ok(identifier) => {
      emit_auto_launch_activity(context, AutoLaunchActivity::{
        operation: "enable",
        identifier: Some(identifier),
      })
      Ok(MutationReply::{ changed: true })
    }
  }
}

///|
/// Disables the resolved native startup entry.
#lepus.command(name="disable")
async fn disable(
  context : @lepus.AppCommandExtensionContext,
  name : String,
  path : String?,
  launch_in_background : Bool?,
  background_arg : String?,
  extra_arguments : Array[String]?,
  identifier : String?,
) -> Result[MutationReply, String] {
  match
    disable_auto_launch(
      auto_launch_payload(
        name, path, launch_in_background, background_arg, extra_arguments, identifier,
      ),
    ) {
    Err(error) => Err(error)
    Ok(identifier) => {
      emit_auto_launch_activity(context, AutoLaunchActivity::{
        operation: "disable",
        identifier: Some(identifier),
      })
      Ok(MutationReply::{ changed: true })
    }
  }
}

///|
#lepus.event(name="activity")
struct AutoLaunchActivity {
  operation : String
  identifier : String?
} derive(ToJson, FromJson, Debug, Eq)
