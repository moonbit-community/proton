///|
priv struct EventCallbacks {
  received : (String) -> @cmd.Cmd
  failure : (@proton_client.ClientFailure) -> @cmd.Cmd
}

///|
priv suberror EventSubscription {
  EventSubscription(
    route~ : String,
    client~ : @proton_client.Client,
    callbacks~ : EventCallbacks,
    ready~ : @cmd.Cmd,
    invalid~ : String?
  )
}

///|
/// Invokes a command as a one-shot effect, suitable for explicit writes.
/// This command does not own component-scoped query state.
pub fn[Request : ToJson, Response : @json.FromJson] invoke(
  command : @proton_contract.Command[Request, Response],
  request : Request,
  success : (Response) -> @cmd.Cmd,
  failure : (@proton_client.ClientFailure) -> @cmd.Cmd,
  client? : @proton_client.Client = @proton_client.desktop,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    // Rabbita runs raw JS async functions outside moonbitlang/async's task
    // context. Use the callback boundary for this one-shot effect.
    ignore(
      client.invoke_with_callbacks(
        command,
        request,
        value => scheduler.add(success(value)),
        error => scheduler.add(failure(error)),
      ),
    )
  })
}

///|
/// Subscribes within the owning Rabbita state scope. Each installed subscription
/// owns its callbacks. Use distinct keys for multiple consumers in one scope.
/// Increment retry to explicitly reinstall a failed subscription.
pub fn[Payload : @json.FromJson] subscribe(
  event : @proton_contract.Event[Payload],
  received : (Payload) -> @cmd.Cmd,
  failure : (@proton_client.ClientFailure) -> @cmd.Cmd,
  key? : String = "",
  retry? : Int = 0,
  ready? : @cmd.Cmd = @cmd.none,
  client? : @proton_client.Client = @proton_client.desktop,
) -> @sub.Sub {
  let route = event.contract_route().operation_name()
  let invalid = try {
    event.validate()
    None
  } catch {
    error => Some(error.message())
  }
  let callbacks : EventCallbacks = {
    received: raw => {
      let value : Payload = @json.from_json(@json.parse(raw)) catch {
        error =>
          return failure(@proton_client.EventDecode(message=error.to_string()))
      }
      received(value)
    },
    failure,
  }
  let payload = EventSubscription(route~, client~, callbacks~, ready~, invalid~)
  @sub.custom_sub(
    ["proton:event", route, key, retry.to_string()].to_json().stringify(),
    @sub.Local,
    payload,
    @sub.SubLoader(load_event_subscription),
  )
}

///|
fn load_event_subscription(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  guard payload
    is EventSubscription(route~, client~, callbacks~, ready~, invalid~) else {
    return None
  }
  let slot = Ref(callbacks)
  let listener = try {
    if invalid is Some(message) {
      raise @proton_client.InvalidContract(message~)
    }
    Some(
      client.listen_json(route, raw => scheduler.add((slot.val.received)(raw))),
    )
  } catch {
    error => {
      scheduler.add((slot.val.failure)(error))
      None
    }
  }
  if listener is Some(_) {
    scheduler.add(ready)
  }
  Some({
    unload: _ => {
      match listener {
        Some(listener) => listener.close()
        None => ()
      }
    },
    update_tagger: updated => {
      if updated
        is EventSubscription(route=new_route, callbacks=new_callbacks, ..) &&
        new_route == route {
        slot.val = new_callbacks
      }
    },
  })
}
