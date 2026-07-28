///|
pub(all) struct SupportRequest {} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct AutoLaunchRequest {
  name : String
  path : String?
  launch_in_background : Bool?
  background_arg : String?
  extra_arguments : Array[String]?
  identifier : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupportReply {
  supported : Bool
  platform : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct AutoLaunchReply {
  name : String
  path : String
  identifier : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct EnabledReply {
  enabled : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct MutationReply {
  changed : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct AutoLaunchActivity {
  operation : String
  identifier : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub let extension : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="justjavac/proton-auto-launch",
  js_namespace="autoLaunch",
)

///|
pub let support : @proton_contract.Command[SupportRequest, SupportReply] = extension.command(
  "support",
)

///|
pub let describe : @proton_contract.Command[AutoLaunchRequest, AutoLaunchReply] = extension.command(
  "describe",
)

///|
pub let is_enabled : @proton_contract.Command[AutoLaunchRequest, EnabledReply] = extension.command(
  "isEnabled",
)

///|
pub let enable : @proton_contract.Command[AutoLaunchRequest, MutationReply] = extension.command(
  "enable",
)

///|
pub let disable : @proton_contract.Command[AutoLaunchRequest, MutationReply] = extension.command(
  "disable",
)

///|
pub let activity : @proton_contract.Event[AutoLaunchActivity] = extension.event(
  "activity",
)
