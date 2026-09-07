///|
struct TestScheduler {
  queued_commands : Ref[Int]
}

///|
fn TestScheduler::TestScheduler() -> TestScheduler {
  TestScheduler::{ queued_commands: Ref(0), }
}

///|
#warnings("-alert_experimental")
impl @cmd.Context for TestScheduler with fn get_origin(_self) {
  "https://example.test"
}

///|
#warnings("-alert_experimental")
impl @cmd.Context for TestScheduler with fn inject_url_changed(_self, _url) {
  @cmd.none
}

///|
#warnings("-alert_experimental")
impl @cmd.Context for TestScheduler with fn inject_url_request(_self, _url) {
  @cmd.none
}

///|
#warnings("-alert_experimental")
impl @cmd.Scheduler for TestScheduler with fn queue_command(self, _command) {
  self.queued_commands.val += 1
}

///|
#warnings("-alert_experimental")
impl @cmd.Scheduler for TestScheduler with fn set_url_changed_injector(
  _self,
  _injector,
) {
  ()
}

///|
#warnings("-alert_experimental")
impl @cmd.Scheduler for TestScheduler with fn set_url_request_injector(
  _self,
  _injector,
) {
  ()
}

///|
fn test_event_payload(
  client : @proton_client.Client,
  received : (String) -> @cmd.Cmd,
  failure? : (@proton_client.ClientFailure) -> @cmd.Cmd = _ => @cmd.none,
) -> Error {
  EventSubscription(
    route="app:changed",
    client~,
    callbacks={ received, failure, },
    ready=@cmd.none,
    invalid=None,
  )
}

///|
test "independent subscription installations cannot overwrite each other" {
  let listeners : Array[(String) -> Unit] = []
  let closes = Ref(0)
  let client = @proton_client.Client(invoke=(_, _, _, _) => () => (), subscribe=(
    _,
    received,
  ) => {
    listeners.push(received)
    () => closes.val += 1
  })
  let first = Ref("")
  let second = Ref("")
  let scheduler = TestScheduler()
  let a = load_event_subscription(
    test_event_payload(client, value => {
      first.val = value
      @cmd.none
    }),
    scheduler,
  ).unwrap()
  let b = load_event_subscription(
    test_event_payload(client, value => {
      second.val = value
      @cmd.none
    }),
    scheduler,
  ).unwrap()
  ignore(
    subscribe(
      @proton_contract.event("changed"),
      (_ : String) => @cmd.none,
      _ => @cmd.none,
      client~,
    ),
  )
  listeners[0]("first")
  listeners[1]("second")
  assert_eq(first.val, "first")
  assert_eq(second.val, "second")
  (a.update_tagger)(
    test_event_payload(client, value => {
      first.val = "updated:" + value
      @cmd.none
    }),
  )
  listeners[0]("next")
  listeners[1]("next")
  assert_eq(first.val, "updated:next")
  assert_eq(second.val, "next")
  assert_eq(listeners.length(), 2)
  (a.unload)(scheduler)
  (a.unload)(scheduler)
  listeners[0]("late")
  listeners[1]("still live")
  assert_eq(first.val, "updated:next")
  assert_eq(second.val, "still live")
  assert_eq(closes.val, 1)
  (b.unload)(scheduler)
  assert_eq(closes.val, 2)
}

///|
test "installation failure reports once and a new installation can retry" {
  let available = Ref(false)
  let attempts = Ref(0)
  let failures = Ref(0)
  let client = @proton_client.Client(invoke=(_, _, _, _) => () => (), subscribe=(
    _,
    _,
  ) => {
    attempts.val += 1
    guard available.val else { raise @proton_client.BridgeUnavailable }
    () => ()
  })
  let payload = test_event_payload(client, _ => @cmd.none, failure=_ => {
    failures.val += 1
    @cmd.none
  })
  let scheduler = TestScheduler()
  let failed = load_event_subscription(payload, scheduler).unwrap()
  (failed.update_tagger)(payload)
  assert_eq(attempts.val, 1)
  assert_eq(failures.val, 1)
  available.val = true
  (failed.unload)(scheduler)
  let retried = load_event_subscription(payload, scheduler).unwrap()
  assert_eq(attempts.val, 2)
  (retried.unload)(scheduler)
}
