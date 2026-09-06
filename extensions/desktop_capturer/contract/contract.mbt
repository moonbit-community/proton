///|
pub(all) struct GetSourcesRequest {
  types : Array[String]
  thumbnail_width : Int?
  thumbnail_height : Int?
} derive(ToJson, FromJson, Debug, Eq)

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
pub(all) struct GetSourcesReply {
  sources : Array[Source]
} derive(ToJson, FromJson, Debug, Eq)

///|
pub let get_sources : @proton_contract.Command[
  GetSourcesRequest,
  GetSourcesReply,
] = extension.command("getSources")
