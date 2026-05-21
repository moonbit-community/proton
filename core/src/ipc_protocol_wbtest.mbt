///|
struct IpcTestPayload {
  left : Int
  right : Int
} derive(ToJson, FromJson, Eq, Debug)

///|
struct IpcTestReply {
  total : Int
} derive(ToJson, FromJson, Eq, Debug)

///|
test "ipc request and response round trip through json" {
  let payload = IpcTestPayload::{ left: 2, right: 5 }
  let request = IpcOpRequest::new(
    "req-1",
    "ext:math/sum",
    ToJson::to_json(payload),
  )
  let parsed_request = parse_ipc_op_request(request.stringify())
  @debug.assert_eq(parsed_request, Ok(request))

  let reply = IpcOpResponse::ok(
    "req-1",
    ToJson::to_json(IpcTestReply::{ total: 7 }),
  )
  let parsed_reply = parse_ipc_op_response(reply.stringify())
  @debug.assert_eq(parsed_reply, Ok(reply))
}

///|
test "mbt process host dispatches sync ipc ops" {
  let host = MbtProcessHost::new(worker_count=1)
  host.op("ext:math/sum", fn(payload : IpcTestPayload) {
    IpcTestReply::{ total: payload.left + payload.right }
  })
  let request = IpcOpRequest::new(
    "req-2",
    "ext:math/sum",
    ToJson::to_json(IpcTestPayload::{ left: 13, right: 29 }),
  )
  let mut response : IpcOpResponse? = None
  host.dispatch(request, fn(reply) { response = Some(reply) })
  @debug.assert_eq(
    response,
    Some(
      IpcOpResponse::ok("req-2", ToJson::to_json(IpcTestReply::{ total: 42 })),
    ),
  )
  host.close()
}

///|
async test "mbt process host runs line-delimited ipc over async pipes" {
  let host = MbtProcessHost::new(worker_count=1)
  host.op("ext:math/sum", fn(payload : IpcTestPayload) {
    IpcTestReply::{ total: payload.left + payload.right }
  })
  let request = IpcOpRequest::new(
    "req-stdio",
    "ext:math/sum",
    ToJson::to_json(IpcTestPayload::{ left: 20, right: 22 }),
  )
  let (host_input, caller_input) = @io.pipe()
  let (caller_output, host_output) = @io.pipe()
  @async.with_task_group(group => {
    group.spawn_bg(() => host.run_io(host_input, host_output))
    caller_input.write(request.stringify() + "\n")
    caller_input.close()
    let raw_response = caller_output.read_until("\n").unwrap_or("")
    let response = parse_ipc_op_response(
      raw_response.trim(chars="\r\n").to_owned(),
    )
    @debug.assert_eq(
      response,
      Ok(
        IpcOpResponse::ok(
          "req-stdio",
          ToJson::to_json(IpcTestReply::{ total: 42 }),
        ),
      ),
    )
  })
  host.close()
}
