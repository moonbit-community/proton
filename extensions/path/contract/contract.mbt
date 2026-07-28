///|
pub(all) struct PathRequest {
  path : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct BasenameRequest {
  path : String
  suffix : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct JoinRequest {
  left : String
  right : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct PathsRequest {
  paths : Array[String]
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct RelativeRequest {
  path : String
  base : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct PathReply {
  path : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct BasenameReply {
  name : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct ExtnameReply {
  ext : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct IsAbsoluteReply {
  is_absolute : Bool
} derive(ToJson, FromJson, Debug, Eq)

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
