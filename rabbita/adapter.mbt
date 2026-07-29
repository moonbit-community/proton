///|
priv struct EventTaggers[Payload] {
  received : (Payload) -> @cmd.Cmd
  failure : (@proton_client.ClientFailure) -> @cmd.Cmd
}

///|
priv enum EventListenerInstallation {
  Installed(@proton_client.Subscription)
  TerminalFailure
}

///|
let event_tagger_slots : Map[String, @rabbita_js.Value] = Map([])

///|
priv suberror ProtonEventSubscription {
  ProtonEventSubscription(route~ : String, tagger_slot~ : @rabbita_js.Value)
  InvalidProtonEventSubscription(
    message~ : String,
    notify~ : (@proton_client.ClientFailure) -> @cmd.Cmd
  )
}

///|
/// Invokes a typed Proton command as one Rabbita command.
///
/// Success and failure are separate callbacks so application messages do not
/// need to expose transport-oriented `Result` values.
pub fn[Request : ToJson, Response : @json.FromJson] invoke(
  command : @proton_contract.Command[Request, Response],
  request : Request,
  success : (Response) -> @cmd.Cmd,
  failure : (@proton_client.ClientFailure) -> @cmd.Cmd,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @proton_client.invoke_with_callbacks(
      command,
      request,
      response => @cmd.Scheduler::add(scheduler, success(response)),
      error => @cmd.Scheduler::add(scheduler, failure(error)),
    )
  })
}

///|
/// Subscribes to one typed Proton event as a stable Rabbita subscription.
///
/// Recomputing the subscription updates its taggers without reinstalling the
/// renderer listener. A malformed event reports one failure and leaves the
/// subscription active.
///
/// An initial installation failure is reported once and retained as a terminal
/// subscription for that key. This prevents the failure message from causing an
/// immediate retry loop. Remove the subscription for one update and add it
/// again to retry explicitly.
pub fn[Payload : @json.FromJson] subscribe(
  event : @proton_contract.Event[Payload],
  received : (Payload) -> @cmd.Cmd,
  failure : (@proton_client.ClientFailure) -> @cmd.Cmd,
) -> @sub.Sub {
  let route = event.contract_route().operation_name()
  event.validate() catch {
    error => return invalid_event_subscription(route, error.message(), failure)
  }
  let tagger_slot = update_event_tagger_slot(route, EventTaggers::{
    received,
    failure,
  })
  let payload = ProtonEventSubscription(
    route~,
    tagger_slot=@rabbita_js.Value::cast_from(tagger_slot),
  )
  @sub.custom_sub(
    subscription_key(route),
    @sub.Local,
    payload,
    @sub.SubLoader((payload, scheduler) => {
      guard payload
        is ProtonEventSubscription(route=payload_route, tagger_slot=erased_slot) &&
        payload_route == route else {
        return None
      }
      let slot : Ref[EventTaggers[Payload]] = erased_slot.cast()
      load_event_subscription(event, route, slot, scheduler)
    }),
  )
}

///|
fn invalid_event_subscription(
  route : String,
  message : String,
  notify : (@proton_client.ClientFailure) -> @cmd.Cmd,
) -> @sub.Sub {
  let payload = InvalidProtonEventSubscription(message~, notify~)
  @sub.custom_sub(
    subscription_key(route) + ":invalid",
    @sub.Local,
    payload,
    @sub.SubLoader((payload, scheduler) => {
      guard payload is InvalidProtonEventSubscription(message~, notify~) else {
        return None
      }
      @cmd.Scheduler::add(
        scheduler,
        notify(@proton_client.InvalidContract(message~)),
      )
      Some({ unload: _scheduler => (), update_tagger: _payload => () })
    }),
  )
}

///|
fn subscription_key(route : String) -> String {
  "proton:event:" + route
}

///|
fn[Payload] update_event_tagger_slot(
  route : String,
  taggers : EventTaggers[Payload],
) -> Ref[EventTaggers[Payload]] {
  match event_tagger_slots.get(route) {
    Some(erased_slot) => {
      let slot : Ref[EventTaggers[Payload]] = erased_slot.cast()
      slot.val = taggers
      slot
    }
    None => {
      let slot = Ref(taggers)
      event_tagger_slots[route] = @rabbita_js.Value::cast_from(slot)
      slot
    }
  }
}

///|
fn[Payload : @json.FromJson] load_event_subscription(
  event : @proton_contract.Event[Payload],
  route : String,
  tagger_slot : Ref[EventTaggers[Payload]],
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  let installation = try
    @proton_client.subscribe(
      event,
      value => @cmd.Scheduler::add(scheduler, (tagger_slot.val.received)(value)),
      error => @cmd.Scheduler::add(scheduler, (tagger_slot.val.failure)(error)),
    )
  catch {
    error => {
      @cmd.Scheduler::add(scheduler, (tagger_slot.val.failure)(error))
      TerminalFailure
    }
  } noraise {
    subscription => Installed(subscription)
  }
  Some({
    unload: _scheduler => {
      match installation {
        Installed(subscription) => subscription.close()
        TerminalFailure => ()
      }
    },
    update_tagger: new_payload => {
      guard new_payload
        is ProtonEventSubscription(route=new_route, tagger_slot=new_erased_slot) &&
        new_route == route else {
        return
      }
      let new_slot : Ref[EventTaggers[Payload]] = new_erased_slot.cast()
      tagger_slot.val = new_slot.val
    },
  })
}
