///|
/// A single HTTP request to make on behalf of the renderer.
#derive(ToJson, FromJson, Debug, Eq)
pub(all) struct Request {
  http_method : String
  url : String
  headers : Map[String, String]
  body : String?
}

///|
pub extend Request with Eq::{not_equal, equal}

///|
pub extend Request with Debug::{to_repr}

///|
pub extend Request with ToJson::{to_json}

///|
pub extend Request with FromJson::{from_json}

///|
/// The response returned from an HTTP request.
#derive(ToJson, FromJson, Debug, Eq)
pub(all) struct Response {
  status : Int32
  status_text : String
  headers : Map[String, String]
  body : String
}

///|
pub extend Response with Eq::{not_equal, equal}

///|
pub extend Response with Debug::{to_repr}

///|
pub extend Response with ToJson::{to_json}

///|
pub extend Response with FromJson::{from_json}

///|
pub let request : @proton_contract.Command[Request, Response] = extension.command(
  "request",
)
