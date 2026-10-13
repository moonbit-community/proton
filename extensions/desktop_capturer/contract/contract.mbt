///|
pub(all) struct GetSourcesRequest {
  types : Array[String]
  thumbnail_width : Int32?
  thumbnail_height : Int32?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend GetSourcesRequest with ToJson::{to_json}

///|
pub extend GetSourcesRequest with FromJson::{from_json}

///|
pub extend GetSourcesRequest with Debug::{to_repr}

///|
pub extend GetSourcesRequest with Eq::{not_equal, equal}

///|
pub(all) struct Source {
  id : String
  name : String
  display_id : String
  x : Int32
  y : Int32
  width : Int32
  height : Int32
  thumbnail : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend Source with ToJson::{to_json}

///|
pub extend Source with FromJson::{from_json}

///|
pub extend Source with Debug::{to_repr}

///|
pub extend Source with Eq::{not_equal, equal}

///|
pub(all) struct GetSourcesReply {
  sources : Array[Source]
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend GetSourcesReply with ToJson::{to_json}

///|
pub extend GetSourcesReply with FromJson::{from_json}

///|
pub extend GetSourcesReply with Debug::{to_repr}

///|
pub extend GetSourcesReply with Eq::{not_equal, equal}

///|
pub let get_sources : @proton_contract.Command[
  GetSourcesRequest,
  GetSourcesReply,
] = extension.command("getSources")
