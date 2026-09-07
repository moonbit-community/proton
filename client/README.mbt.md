# Proton Client

`moonbit-community/proton_client` invokes typed Proton contracts from the active
renderer page. It uses the bridge installed by Proton before application
scripts run; the default client needs no configuration.

```moonbit nocheck
///|
async fn load_todos {
  let snapshot = @proton_client.invoke(@shared.list_todos, {})
  render(snapshot)
}
```

Requests are encoded and responses are decoded at the client boundary.
Transport, timeout, cancellation, remote execution, and decoding failures are
raised as `ClientFailure`.

## Isolated clients and cancellation

Construct a Client with callback-based JSON invocation and listener functions
for browser previews or deterministic tests. Each instance is independent;
tests do not need to replace the global desktop bridge. Use client.invoke,
client.invoke_with_callbacks, and client.subscribe with the same shared
descriptors as the desktop convenience functions.

The cancellation function returned by invoke_with_callbacks is idempotent and
suppresses late success/failure callbacks even if the transport ignores abort.
Async invocation requires a moonbitlang/async task context; adapters whose
runtime owns scheduling should use invoke_with_callbacks. Async task
cancellation also cancels the pending invocation. Cancellation ends
observation and requests backend cancellation; it never promises to undo a
completed write. Closing a subscription suppresses queued notifications.
Malformed events report EventDecode without removing the listener.

Expected business failures belong in the response enum, not in string matching
against ClientFailure. Events are live notifications with no replay or delivery
acknowledgement. State consumers should subscribe before querying and reject
outdated query results.
