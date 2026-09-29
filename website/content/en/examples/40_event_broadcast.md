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
