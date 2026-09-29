# Typed events

Progress events emitted during an asynchronous command.

[40_event_broadcast](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/40_event_broadcast) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/40_event_broadcast/main.mbt), [app.html](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/40_event_broadcast/app.html)

## Behavior

Starting the ticker produces tick events and a done event. The command also returns its collected result. The run_id distinguishes runs.

## Run

[Environment requirements](../introduction/installation.md) apply. From the checked-out repository root:

```sh
moon -C examples run 40_event_broadcast --target native
```

## Limits and interpretation

Events and command responses serve different purposes. Register listeners before starting a run; an event is not a durable history or an acknowledgement.

## Key code and design

Excerpt from the entry point; use the source link above for the complete context.

```moonbit
async fn run_ticker(
  context : @proton.CommandContext,
  payload : StartPayload,
) -> TickerResult {
  let count = clamp(payload.count, 1, 20)
  let interval_ms = clamp(payload.interval_ms, 100, 2000)
  let ticks : Array[TickEvent] = []
  for index in 1..<=count {
    @async.sleep(interval_ms)
    let tick = TickEvent::{
      run_id: payload.run_id,
      index,
      total: count,
      remaining: count - index,
    }
    ticks.push(tick)
    context.emit(tick_event, tick)
  }
  let done = DoneEvent::{ run_id: payload.run_id, total: count, }
  context.emit(done_event, done)
  TickerResult::{ ticks, done, }
}
```

A typed extension binds start to run_ticker. The handler awaits between ticks and emits tick/done notifications before returning a final TickerResult. Progress events and the command result have separate roles: a displayed tick is not completion of the command.

The count and interval are clamped by the backend. Reuse the request id in your UI to distinguish overlapping runs, close subscriptions with their owner, and handle request cancellation. Despite the historical directory name, this is not a durable broadcast log.
