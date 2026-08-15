///|
/// A single HTTP request to make on behalf of the renderer.
pub(all) struct Request {
  http_method : String
  url : String
  headers : Map[String, String]
  body : String?
} derive(ToJson, FromJson, Debug, Eq)

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
pub(all) struct Response {
  status : Int
  status_text : String
  headers : Map[String, String]
  body : String
} derive(ToJson, FromJson, Debug, Eq)

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
