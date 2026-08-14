///|
/// A single HTTP request to make on behalf of the renderer.
pub(all) struct Request {
  http_method : String
  url : String
  headers : Map[String, String]
  body : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
/// The response returned from an HTTP request.
pub(all) struct Response {
  status : Int
  status_text : String
  headers : Map[String, String]
  body : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub let request : @proton_contract.Command[Request, Response] = extension.command(
  "request",
)
