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
  let request = @ipc.IpcOpRequest::new(
    "req-1",
    "ext:math/sum",
    ToJson::to_json(payload),
  )
  let parsed_request = @ipc.parse_ipc_op_request(request.stringify())
  @debug.assert_eq(parsed_request, Ok(request))

  let reply = @ipc.IpcOpResponse::ok(
    "req-1",
    ToJson::to_json(IpcTestReply::{ total: 7 }),
  )
  let parsed_reply = @ipc.parse_ipc_op_response(reply.stringify())
  @debug.assert_eq(parsed_reply, Ok(reply))
}

///|
test "mbt process host dispatches sync ipc ops" {
  let host = MbtProcessHost::new()
  host.op("ext:math/sum", fn(payload : IpcTestPayload) {
    IpcTestReply::{ total: payload.left + payload.right }
  })
  host.seal_registrations()
  let request = @ipc.IpcOpRequest::new(
    "req-2",
    "ext:math/sum",
    ToJson::to_json(IpcTestPayload::{ left: 13, right: 29 }),
  )
  let mut response : @ipc.IpcOpResponse? = None
  host.dispatch(request, fn(reply) { response = Some(reply) })
  @debug.assert_eq(
    response,
    Some(
      @ipc.IpcOpResponse::ok(
        "req-2",
        ToJson::to_json(IpcTestReply::{ total: 42 }),
      ),
    ),
  )
  host.close()
}

///|
test "mbt process host validates direct ipc requests" {
  let host = MbtProcessHost::new()
  host.op("app:ping", fn(_payload : Json) { Json::string("pong") })
  let invalid = @ipc.IpcOpRequest::{
    version: @ipc.protocol_version() + 1,
    id: "req-invalid",
    name: "app:ping",
    payload: Json::null(),
  }
  let mut response : @ipc.IpcOpResponse? = None
  host.dispatch(invalid, fn(reply) { response = Some(reply) })
  @debug.assert_eq(
    response,
    Some(
      @ipc.IpcOpResponse::err(
        "req-invalid",
        "Unsupported IPC protocol version: " +
        (@ipc.protocol_version() + 1).to_string(),
      ),
    ),
  )
  host.close()
}

///|
test "command hosts expose registered op snapshots" {
  let mbt_host = MbtProcessHost::new()
  mbt_host.op("app:ping", fn(_payload : Json) { Json::string("pong") })
  let mbt_ops = mbt_host.registered_ops()
  mbt_ops.push("app:mutated")
  @debug.assert_eq(mbt_host.registered_ops(), ["app:ping"])
  mbt_host.close()

  let app_host = AppCommandHost::new()
  app_host.op("app:hello", fn(_payload : Json) { Json::string("world") })
  let app_ops = app_host.registered_ops()
  app_ops.push("app:mutated")
  @debug.assert_eq(app_host.registered_ops(), ["app:hello"])
  app_host.close()
}

///|
test "op registry rejects empty op names" {
  match validate_op_name("") {
    Err(error) => assert_eq(error, "op name must not be empty")
    Ok(_) => abort("expected empty op name error")
  }
  match validate_op_name("  ") {
    Err(error) => assert_eq(error, "op name must not be empty")
    Ok(_) => abort("expected blank op name error")
  }
  match validate_op_name("ext:math/sum") {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}

///|
test "ipc bridge runtime validates remote extension descriptors" {
  let descriptor = @ipc.IpcExtensionDescriptor::new("vendor/demo", "demo", [
    @ipc.IpcExtensionApi::new("ping"),
  ])
  match
    validate_ipc_bridge_runtime_config("bridge", ["ext:demo/ping"], [descriptor]) {
    Ok(_) => ()
    Err(error) => abort(error)
  }

  match
    validate_ipc_bridge_runtime_config("bridge", ["ext:demo/other"], [
      descriptor,
    ]) {
    Err(error) =>
      assert_eq(
        error, "install_ipc_bridge_runtime: extension API is missing op: ext:demo/ping",
      )
    Ok(_) => abort("expected missing remote extension op error")
  }

  let duplicate_api = @ipc.IpcExtensionDescriptor::new("vendor/demo", "demo", [
    @ipc.IpcExtensionApi::new("ping"),
    @ipc.IpcExtensionApi::new("ping"),
  ])
  match
    validate_ipc_bridge_runtime_config("bridge", ["ext:demo/ping"], [
      duplicate_api,
    ]) {
    Err(error) =>
      assert_eq(
        error, "install_ipc_bridge_runtime: duplicate extension API: vendor/demo.ping",
      )
    Ok(_) => abort("expected duplicate remote extension API error")
  }
}

///|
test "ipc bridge runtime rejects empty bridge script" {
  match validate_ipc_bridge_runtime_config(" ", ["app:ping"], []) {
    Err(error) =>
      assert_eq(
        error, "install_ipc_bridge_runtime: bridge script must not be empty",
      )
    Ok(_) => abort("expected empty IPC bridge script error")
  }
}

///|
test "standalone ipc extension install validates descriptor shape" {
  let empty_api = @ipc.IpcExtensionDescriptor::new("vendor/demo", "demo", [])
  match validate_ipc_extension_install_descriptor(empty_api) {
    Err(error) =>
      assert_eq(
        error, "install_ipc_extension: extension must expose at least one API: vendor/demo",
      )
    Ok(_) => abort("expected empty standalone IPC extension API error")
  }

  let blank_api = @ipc.IpcExtensionDescriptor::new("vendor/demo", "demo", [
    @ipc.IpcExtensionApi::new(" "),
  ])
  match validate_ipc_extension_install_descriptor(blank_api) {
    Err(error) =>
      assert_eq(
        error, "install_ipc_extension: extension API name must not be empty: vendor/demo",
      )
    Ok(_) => abort("expected blank standalone IPC extension API error")
  }

  let duplicate_api = @ipc.IpcExtensionDescriptor::new("vendor/demo", "demo", [
    @ipc.IpcExtensionApi::new("ping"),
    @ipc.IpcExtensionApi::new("ping"),
  ])
  match validate_ipc_extension_install_descriptor(duplicate_api) {
    Err(error) =>
      assert_eq(
        error, "install_ipc_extension: duplicate extension API: vendor/demo.ping",
      )
    Ok(_) => abort("expected duplicate standalone IPC extension API error")
  }
}
