///|
test "clients are isolated and request completion is delivered once" {
  let command : @proton_contract.Command[Unit, String] = @proton_contract.command(
    "read",
  )
  let first = @proton_client.Client(
    invoke=(_, _, success, failure) => {
      success("\"one\"")
      success("\"duplicate\"")
      failure(@proton_client.TransportFailure(message="late"))
      () => ()
    },
    subscribe=(_, _) => () => (),
  )
  let second = @proton_client.Client(
    invoke=(_, _, success, _) => {
      success("\"two\"")
      () => ()
    },
    subscribe=(_, _) => () => (),
  )
  let values : Array[String] = []
  ignore(
    first.invoke_with_callbacks(command, (), value => values.push(value), _ => {
      values.push("error")
    }),
  )
  ignore(
    second.invoke_with_callbacks(command, (), value => values.push(value), _ => {
      values.push("error")
    }),
  )
  assert_eq(values, ["one", "two"])
}

///|
test "cancellation suppresses both success and failure even if transport ignores it" {
  let command : @proton_contract.Command[Unit, String] = @proton_contract.command(
    "read",
  )
  let success : Ref[(String) -> Unit] = Ref(_ => ())
  let failure : Ref[(@proton_client.ClientFailure) -> Unit] = Ref(_ => ())
  let cancels = Ref(0)
  let deliveries = Ref(0)
  let client = @proton_client.Client(
    invoke=(_, _, ok, err) => {
      success.val = ok
      failure.val = err
      () => cancels.val += 1
    },
    subscribe=(_, _) => () => (),
  )
  let cancel = client.invoke_with_callbacks(
    command,
    (),
    _ => deliveries.val += 1,
    _ => deliveries.val += 1,
  )
  cancel()
  cancel()
  (success.val)("\"late\"")
  (failure.val)(@proton_client.TransportFailure(message="late"))
  assert_eq(deliveries.val, 0)
  assert_eq(cancels.val, 1)
}

///|
test "independent typed listeners survive malformed events and close separately" {
  let listeners : Array[(String) -> Unit] = []
  let closes = Ref(0)
  let client = @proton_client.Client(invoke=(_, _, _, _) => () => (), subscribe=(
    _,
    received,
  ) => {
    listeners.push(received)
    () => closes.val += 1
  })
  let event : @proton_contract.Event[Int] = @proton_contract.event("changed")
  let first = Ref(0)
  let second = Ref(0)
  let failures = Ref(0)
  let a = client.subscribe(event, x => first.val = x, _ => failures.val += 1)
  let b = client.subscribe(event, x => second.val = x, _ => failures.val += 1)
  listeners[0]("invalid")
  listeners[0]("3")
  listeners[1]("4")
  assert_eq(failures.val, 1)
  assert_eq(first.val, 3)
  assert_eq(second.val, 4)
  a.close()
  listeners[0]("5")
  listeners[1]("6")
  assert_eq(first.val, 3)
  assert_eq(second.val, 6)
  b.close()
  assert_eq(closes.val, 2)
}

///|
async test "cancelling an async invocation aborts its transport" {
  let cancellations = Ref(0)
  let started = Ref(false)
  let client = @proton_client.Client(
    invoke=(_, _, _, _) => {
      started.val = true
      () => cancellations.val += 1
    },
    subscribe=(_, _) => () => (),
  )
  let command : @proton_contract.Command[Unit, String] = @proton_contract.command(
    "pending",
  )
  @async.with_task_group(group => {
    let task = group.spawn(
      () => client.invoke(command, ()) |> ignore,
      no_wait=true,
    )
    @async.pause()
    assert_true(started.val)
    task.cancel()
  }) catch {
    @proton_client.RequestCancelled => ()
    error => raise error
  }
  assert_eq(cancellations.val, 1)
}
