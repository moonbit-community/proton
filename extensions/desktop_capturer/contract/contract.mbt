///|
pub(all) struct GetSourcesRequest {
  types : Array[String]
  thumbnail_width : Int?
  thumbnail_height : Int?
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
  x : Int
  y : Int
  width : Int
  height : Int
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
