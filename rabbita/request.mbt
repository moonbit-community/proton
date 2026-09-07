///|
priv suberror ManagedRequest {
  ManagedRequest(start~ : ((@cmd.Cmd) -> Unit) -> () -> Unit)
}

///|
/// Runs one request for this component's (key, revision) identity. Removing
/// the subscription cancels observation and the pending transport request.
/// Change revision for a replacement query or explicit retry. A completed
/// request remains inert until removed or replaced, preventing feedback loops.
/// Callbacks capture the request's originating state. Cancellation does not
/// undo backend writes; application messages should also carry the revision.
pub fn[Request : ToJson, Response : @json.FromJson] request(
  command : @proton_contract.Command[Request, Response],
  input : Request,
  success : (Response) -> @cmd.Cmd,
  failure : (@proton_client.ClientFailure) -> @cmd.Cmd,
  key~ : String,
  revision~ : Int,
  client? : @proton_client.Client = @proton_client.desktop,
) -> @sub.Sub {
  @sub.custom_sub(
    [
      "proton:request",
      command.contract_route().operation_name(),
      key,
      revision.to_string(),
    ]
    .to_json()
    .stringify(),
    @sub.Local,
    ManagedRequest(start=enqueue => {
      client.invoke_with_callbacks(
        command,
        input,
        value => enqueue(success(value)),
        error => enqueue(failure(error)),
      )
    }),
    @sub.SubLoader(load_request),
  )
}

///|
fn load_request(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  guard payload is ManagedRequest(start~) else { return None }
  let active = Ref(true)
  let cancel = start(command => if active.val { scheduler.add(command) })
  Some({
    unload: _ => {
      if active.val {
        active.val = false
        cancel()
      }
    },
    update_tagger: _ => (),
  })
}
