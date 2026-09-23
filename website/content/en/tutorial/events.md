# Sending events to the frontend

Use events when the backend needs to notify a frontend about a change. This guide extends the greeting command from [calling the backend](commands-events.md): clicking the button still invokes a command, but the displayed message now comes from an event.

## Declare the event

In **`app/main.mbt`**, add this declaration alongside the existing `greet` descriptor, outside `main`:

```moonbit
///|
let greeted : @proton_contract.Event[String] =
  @proton_contract.event("greeted")
```

The event name is `greeted` and its payload is a string. It has no response type: emitting an event does not ask the frontend to return a value.

## Send to the caller

Inside `.commands(...)`, replace the existing `registrar.bind(greet, ...)` call with:

```moonbit
registrar.bind(greet, (context, request) => {
  let message = "Hello, " + request.name + "!"
  context.emit_to_caller(greeted, message)
  message
})
```

`context.emit_to_caller` sends to the page that invoked this command. The final `message` is still the command response. The response and event are separate deliveries; do not rely on a particular ordering between them.

## Listen before triggering work

Replace the contents between `<script>` and `</script>` in the HTML string with the following JavaScript. In the MoonBit multiline string, prefix each line with `#|` as in the previous example:

```javascript
let stopListening;
document.querySelector("#greet").onclick = async () => {
  const result = document.querySelector("#result");
  const app = window.__MoonBit__.app;
  try {
    if (!stopListening) {
      stopListening = app.on("greeted", ({ payload }) => {
        result.textContent = "Event: " + payload;
      });
    }
    await app.greet({ name: document.querySelector("#name").value });
  } catch (error) {
    result.textContent = String(error);
  }
};
window.addEventListener("pagehide", () => {
  stopListening?.();
});
```

Start the app, enter a name, and click **Greet**. The expected message is now “Event: Hello, Ada!”. Clicking again updates it without adding another listener.

The first click installs the listener before invoking the command, so this example does not emit its first notification before subscribing. `app.on` returns an unsubscribe function. Here it is kept until the page leaves; a component-based UI should release it when the owning component is disposed.

## Notify a window outside a command

Background work may need to notify a window after the originating command has completed. The Todo template saves `context.events()` from `window_lifecycle(on_ready=...)` and removes that destination in `on_close`. The saved `WindowEventEmitter` can emit typed events while the window remains alive.

Choose destinations explicitly. Do not retain stale window emitters or treat every event as a global broadcast. See the [complete Todo example](isomorphic.md) for the attach/detach lifecycle.

## Events and state

A listener can miss events while it is absent. For application state, use an event to invalidate data, then query a fresh snapshot. The Todo app subscribes before its initial query and refreshes on `todos_changed`.

Use command results for acknowledgement of requested work. Use events for notifications to observers. If a workflow requires durable delivery or replay, implement that in the application's state model rather than assuming the event bridge provides it.
