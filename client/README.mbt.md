# Proton Client

`moonbit-community/proton_client` invokes typed Proton contracts from the active
renderer page. It uses the bridge installed by Proton before application
scripts run; applications do not construct a client or select a transport.

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
