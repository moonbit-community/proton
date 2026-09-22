# Typed events

[中文](../zh/examples/40_event_broadcast.html)

Progress events emitted during an asynchronous command.

[40_event_broadcast](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/40_event_broadcast) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/40_event_broadcast/main.mbt), [app.html](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/40_event_broadcast/app.html)

## Behavior

Starting the ticker produces tick events and a done event. The command also returns its collected result. The run_id distinguishes runs.

## Run

[Environment requirements](../installation.md) apply. From the checked-out repository root:

```sh
moon -C examples run 40_event_broadcast --target native
```

## Limits and interpretation

Events and command responses serve different purposes. Register listeners before starting a run; an event is not a durable history or an acknowledgement.
