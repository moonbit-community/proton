///|
struct ExtensionNotice {
  message : String
} derive(ToJson, FromJson, Eq, Debug)

///|
struct ExtensionNoticeEvent {
  extension : String
  name : String
  payload : ExtensionNotice
} derive(ToJson, FromJson, Eq, Debug)

///|
struct MultiplyPayload {
  left : Int
  right : Int
} derive(ToJson, FromJson, Eq, Debug)

///|
struct MultiplyReply {
  total : Int
} derive(ToJson, FromJson, Eq, Debug)

///|
struct OpsRuntimeReport {
  direct : MultiplyReply
  extension : MultiplyReply
  event_count : Int
} derive(ToJson, FromJson, Eq, Debug)

///|
struct MixedRuntimeReport {
  local_reply : MultiplyReply
  remote : Bool
} derive(ToJson, FromJson, Eq, Debug)

///|
struct StandaloneIpcExtensionReport {
  has_core : Bool
  has_extension : Bool
  has_op : Bool
} derive(ToJson, FromJson, Eq, Debug)

///|
/// Decodes the single callback argument payload used by the integration tests.
fn[Payload : @json.FromJson] decode_single_argument(
  raw_req : Bytes,
) -> Result[Payload, String] {
  try {
    let request_json : Json = @json.parse(@ffi.from_cstr(raw_req))
    let request_args : Array[Payload] = @json.from_json(request_json)
    expect_single_argument(request_args)
  } catch {
    err => Err(err.to_string())
  }
}

///|
/// Ensures the callback bridge supplied exactly one typed argument.
fn[Payload] expect_single_argument(
  request_args : Array[Payload],
) -> Result[Payload, String] {
  if request_args.length() == 1 {
    Ok(request_args[0])
  } else {
    Err("Expected exactly one argument")
  }
}
