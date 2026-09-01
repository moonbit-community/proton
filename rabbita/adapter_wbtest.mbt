///|
struct EchoResponse {
  value : String
} derive(FromJson)

///|
pub extend EchoResponse with FromJson::{from_json}

///|
struct CountChanged {
  count : Int
} derive(FromJson)

///|
pub extend CountChanged with FromJson::{from_json}

///|
struct TestScheduler {
  queued_commands : Ref[Int]
}

///|
fn TestScheduler::TestScheduler() -> TestScheduler {
  TestScheduler::{ queued_commands: Ref(0), }
}

///|
impl @cmd.Context for TestScheduler with fn get_origin(_self) {
  "https://example.test"
}

///|
impl @cmd.Context for TestScheduler with fn inject_url_changed(_self, _url) {
  @cmd.none
}

///|
impl @cmd.Context for TestScheduler with fn inject_url_request(_self, _url) {
  @cmd.none
}

///|
impl @cmd.Scheduler for TestScheduler with fn queue_command(self, _command) {
  self.queued_commands.val += 1
}

///|
impl @cmd.Scheduler for TestScheduler with fn set_url_changed_injector(
  _self,
  _injector,
) {
  ()
}

///|
impl @cmd.Scheduler for TestScheduler with fn set_url_request_injector(
  _self,
  _injector,
) {
  ()
}

///|
fn TestScheduler::queued_count(self : TestScheduler) -> Int {
  self.queued_commands.val
}

///|
extern "js" fn install_fake_bridge(response_json : String) -> Unit =
  #| (responseJson) => {
  #|   globalThis.__protonRabbitaTest = {
  #|     responseJson,
  #|     listener: null,
  #|     installs: 0,
  #|     signal: null,
  #|   };
  #|   globalThis.__MoonBit__ = {
  #|     core: {
  #|       invokeJson(_route, _requestJson, options) {
  #|         globalThis.__protonRabbitaTest.signal = options && options.signal;
  #|         return {
  #|           then(success) {
  #|             success(globalThis.__protonRabbitaTest.responseJson);
  #|           },
  #|         };
  #|       },
  #|     },
  #|     events: {
  #|       onJson(_route, listener) {
  #|         globalThis.__protonRabbitaTest.listener = listener;
  #|         globalThis.__protonRabbitaTest.installs += 1;
  #|         return () => {
  #|           globalThis.__protonRabbitaTest.listener = null;
  #|         };
  #|       },
  #|     },
  #|   };
  #| }

///|
extern "js" fn remove_fake_bridge() -> Unit =
  #| () => {
  #|   delete globalThis.__MoonBit__;
  #|   delete globalThis.__protonRabbitaTest;
  #| }

///|
extern "js" fn emit_fake_event(payload_json : String) -> Unit =
  #| (payloadJson) => {
  #|   const listener = globalThis.__protonRabbitaTest.listener;
  #|   if (listener) listener(payloadJson);
  #| }

///|
extern "js" fn fake_listener_installs() -> Int =
  #| () => globalThis.__protonRabbitaTest.installs

///|
extern "js" fn fake_has_listener() -> Bool =
  #| () => globalThis.__protonRabbitaTest.listener !== null

///|
extern "js" fn fake_has_abort_signal() -> Bool =
  #| () => Boolean(globalThis.__protonRabbitaTest?.signal)

///|
test "invoke queues bridge work without entering async from an effect" {
  install_fake_bridge("{\"value\":\"pong\"}")
  let scheduler = TestScheduler()
  let echo : @proton_contract.Command[Unit, EchoResponse] = @proton_contract.command(
    "echo",
  )
  @cmd.Scheduler::add(
    scheduler,
    invoke(echo, (), _value => @cmd.none, _error => @cmd.none),
  )
  assert_eq(scheduler.queued_count(), 1)
  assert_false(fake_has_abort_signal())

  remove_fake_bridge()
  @cmd.Scheduler::add(
    scheduler,
    invoke(echo, (), _ => @cmd.none, _error => @cmd.none),
  )
  assert_eq(scheduler.queued_count(), 2)
  assert_false(fake_has_abort_signal())

  install_fake_bridge("{\"value\":\"pong\"}")
  let response = Ref("")
  let failure_code = Ref("")
  ignore(
    @proton_client.invoke_with_callbacks(
      echo,
      (),
      value => response.val = value.value,
      error => {
        failure_code.val = match error {
          @proton_client.BridgeUnavailable => "bridge_unavailable"
          _ => "unexpected"
        }
      },
    ),
  )
  assert_eq(response.val, "pong")
  assert_eq(failure_code.val, "")
  assert_true(fake_has_abort_signal())

  remove_fake_bridge()
  ignore(
    @proton_client.invoke_with_callbacks(echo, (), _value => (), error => {
      failure_code.val = match error {
        @proton_client.BridgeUnavailable => "bridge_unavailable"
        _ => "unexpected"
      }
    }),
  )
  assert_eq(failure_code.val, "bridge_unavailable")
}

///|
test "subscription updates taggers without reinstalling its listener" {
  install_fake_bridge("{}")
  let scheduler = TestScheduler()
  let changed : @proton_contract.Event[CountChanged] = @proton_contract.event(
    "count_changed",
  )
  let first_count = Ref(0)
  let second_count = Ref(0)
  let failures = Ref(0)
  let route = changed.contract_route().operation_name()
  let first_taggers : EventTaggers[CountChanged] = {
    received: value => {
      first_count.val = value.count
      @cmd.none
    },
    failure: _error => {
      failures.val += 1
      @cmd.none
    },
  }
  let tagger_slot = update_event_tagger_slot(route, first_taggers)
  let running = load_event_subscription(changed, route, tagger_slot, scheduler).unwrap()
  assert_eq(fake_listener_installs(), 1)

  ignore(
    subscribe(
      changed,
      value => {
        second_count.val = value.count
        @cmd.none
      },
      _error => {
        failures.val += 1
        @cmd.none
      },
    ),
  )
  assert_eq(fake_listener_installs(), 1)

  emit_fake_event("{\"count\":7}")
  assert_eq(first_count.val, 0)
  assert_eq(second_count.val, 7)
  assert_eq(scheduler.queued_count(), 1)
  emit_fake_event("not json")
  assert_eq(scheduler.queued_count(), 2)
  assert_eq(failures.val, 1)
  assert_true(fake_has_listener())

  (running.unload)(scheduler)
  assert_false(fake_has_listener())
  remove_fake_bridge()
}

///|
test "failed subscription remains terminal until it is reloaded" {
  remove_fake_bridge()
  let scheduler = TestScheduler()
  let changed : @proton_contract.Event[CountChanged] = @proton_contract.event(
    "terminal_subscription_failure",
  )
  let route = changed.contract_route().operation_name()
  let failures = Ref(0)
  let tagger_slot = update_event_tagger_slot(route, {
    received: _value => @cmd.none,
    failure: _error => {
      failures.val += 1
      @cmd.none
    },
  })
  let failed = load_event_subscription(changed, route, tagger_slot, scheduler).unwrap()
  assert_eq(scheduler.queued_count(), 1)
  assert_eq(failures.val, 1)

  install_fake_bridge("{}")
  assert_eq(fake_listener_installs(), 0)
  (failed.update_tagger)(
    ProtonEventSubscription(
      route~,
      tagger_slot=@rabbita_js.Value::cast_from(tagger_slot),
    ),
  )
  assert_eq(fake_listener_installs(), 0)

  (failed.unload)(scheduler)
  let retried = load_event_subscription(changed, route, tagger_slot, scheduler).unwrap()
  assert_eq(fake_listener_installs(), 1)
  (retried.unload)(scheduler)
  remove_fake_bridge()
}

///|
test "duplicate event routes do not overwrite erased tagger slots" {
  let first : @proton_contract.Event[CountChanged] = @proton_contract.event(
    "duplicate_rabbita_event",
  )
  let duplicate : @proton_contract.Event[String] = @proton_contract.event(
    "duplicate_rabbita_event",
  )
  let first_count = Ref(0)
  let duplicate_value = Ref("")
  ignore(
    subscribe(
      first,
      value => {
        first_count.val = value.count
        @cmd.none
      },
      _error => @cmd.none,
    ),
  )
  ignore(
    subscribe(
      duplicate,
      value => {
        duplicate_value.val = value
        @cmd.none
      },
      _error => @cmd.none,
    ),
  )
  let erased_slot = event_tagger_slots
    .get("app:duplicate_rabbita_event")
    .unwrap()
  let slot : Ref[EventTaggers[CountChanged]] = erased_slot.cast()
  ignore((slot.val.received)(CountChanged::{ count: 7, }))
  assert_eq(first_count.val, 7)
  assert_eq(duplicate_value.val, "")
}
