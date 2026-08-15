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
pub extend AutoLaunchRequest with Eq::{not_equal, equal}

///|
pub extend AutoLaunchRequest with Debug::{to_repr}

///|
pub extend AutoLaunchRequest with ToJson::{to_json}

///|
pub extend AutoLaunchRequest with FromJson::{from_json}

///|
pub(all) struct AutoLaunchReply {
  name : String
  path : String
  identifier : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend AutoLaunchReply with Eq::{not_equal, equal}

///|
pub extend AutoLaunchReply with Debug::{to_repr}

///|
pub extend AutoLaunchReply with ToJson::{to_json}

///|
pub extend AutoLaunchReply with FromJson::{from_json}

///|
pub(all) struct EnabledReply {
  enabled : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend EnabledReply with Eq::{not_equal, equal}

///|
pub extend EnabledReply with Debug::{to_repr}

///|
pub extend EnabledReply with ToJson::{to_json}

///|
pub extend EnabledReply with FromJson::{from_json}

///|
pub(all) struct MutationReply {
  changed : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend MutationReply with Eq::{not_equal, equal}

///|
pub extend MutationReply with Debug::{to_repr}

///|
pub extend MutationReply with ToJson::{to_json}

///|
pub extend MutationReply with FromJson::{from_json}

///|
pub(all) struct AutoLaunchActivity {
  operation : String
  identifier : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend AutoLaunchActivity with Eq::{not_equal, equal}

///|
pub extend AutoLaunchActivity with Debug::{to_repr}

///|
pub extend AutoLaunchActivity with ToJson::{to_json}

///|
pub extend AutoLaunchActivity with FromJson::{from_json}

///|
pub let support : @proton_contract.Command[
  @proton_contract.EmptyRequest,
  @proton_contract.SupportReply,
] = extension.command("support")

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
