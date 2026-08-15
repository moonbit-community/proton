///|
pub(all) struct PathRequest {
  path : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend PathRequest with Eq::{not_equal, equal}

///|
pub extend PathRequest with Debug::{to_repr}

///|
pub extend PathRequest with ToJson::{to_json}

///|
pub extend PathRequest with FromJson::{from_json}

///|
pub(all) struct BasenameRequest {
  path : String
  suffix : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend BasenameRequest with Eq::{not_equal, equal}

///|
pub extend BasenameRequest with Debug::{to_repr}

///|
pub extend BasenameRequest with ToJson::{to_json}

///|
pub extend BasenameRequest with FromJson::{from_json}

///|
pub(all) struct JoinRequest {
  left : String
  right : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend JoinRequest with Eq::{not_equal, equal}

///|
pub extend JoinRequest with Debug::{to_repr}

///|
pub extend JoinRequest with ToJson::{to_json}

///|
pub extend JoinRequest with FromJson::{from_json}

///|
pub(all) struct PathsRequest {
  paths : Array[String]
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend PathsRequest with Eq::{not_equal, equal}

///|
pub extend PathsRequest with Debug::{to_repr}

///|
pub extend PathsRequest with ToJson::{to_json}

///|
pub extend PathsRequest with FromJson::{from_json}

///|
pub(all) struct RelativeRequest {
  path : String
  base : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend RelativeRequest with Eq::{not_equal, equal}

///|
pub extend RelativeRequest with Debug::{to_repr}

///|
pub extend RelativeRequest with ToJson::{to_json}

///|
pub extend RelativeRequest with FromJson::{from_json}

///|
pub(all) struct PathReply {
  path : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend PathReply with Eq::{not_equal, equal}

///|
pub extend PathReply with Debug::{to_repr}

///|
pub extend PathReply with ToJson::{to_json}

///|
pub extend PathReply with FromJson::{from_json}

///|
pub(all) struct BasenameReply {
  name : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend BasenameReply with Eq::{not_equal, equal}

///|
pub extend BasenameReply with Debug::{to_repr}

///|
pub extend BasenameReply with ToJson::{to_json}

///|
pub extend BasenameReply with FromJson::{from_json}

///|
pub(all) struct ExtnameReply {
  ext : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend ExtnameReply with Eq::{not_equal, equal}

///|
pub extend ExtnameReply with Debug::{to_repr}

///|
pub extend ExtnameReply with ToJson::{to_json}

///|
pub extend ExtnameReply with FromJson::{from_json}

///|
pub(all) struct IsAbsoluteReply {
  is_absolute : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend IsAbsoluteReply with Eq::{not_equal, equal}

///|
pub extend IsAbsoluteReply with Debug::{to_repr}

///|
pub extend IsAbsoluteReply with ToJson::{to_json}

///|
pub extend IsAbsoluteReply with FromJson::{from_json}

///|
pub let basename : @proton_contract.Command[BasenameRequest, BasenameReply] = extension.command(
  "basename",
)

///|
pub let dirname : @proton_contract.Command[PathRequest, PathReply] = extension.command(
  "dirname",
)

///|
pub let extname : @proton_contract.Command[PathRequest, ExtnameReply] = extension.command(
  "extname",
)

///|
pub let is_absolute : @proton_contract.Command[PathRequest, IsAbsoluteReply] = extension.command(
  "is_absolute",
)

///|
pub let join : @proton_contract.Command[JoinRequest, PathReply] = extension.command(
  "join",
)

///|
pub let join_all : @proton_contract.Command[PathsRequest, PathReply] = extension.command(
  "join_all",
)

///|
pub let normalize : @proton_contract.Command[PathRequest, PathReply] = extension.command(
  "normalize",
)

///|
pub let relative : @proton_contract.Command[RelativeRequest, PathReply] = extension.command(
  "relative",
)

///|
pub let resolve : @proton_contract.Command[PathRequest, PathReply] = extension.command(
  "resolve",
)

///|
pub let resolve_all : @proton_contract.Command[PathsRequest, PathReply] = extension.command(
  "resolve_all",
)
