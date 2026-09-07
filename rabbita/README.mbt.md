# Proton Rabbita

`moonbit-community/proton_rabbita` maps typed Proton commands and events onto Rabbita
`Cmd` and `Sub` values. Transport and JSON handling remain owned by
`moonbit-community/proton_client`.

```mbt check
///|
struct PingRequest {
  value : String
} derive(ToJson)

///|
pub extend PingRequest with ToJson::{to_json}

///|
struct PingReply {
  value : String
} derive(FromJson)

///|
pub extend PingReply with FromJson::{from_json}

///|
test {
  let ping : @proton_contract.Command[PingRequest, PingReply] = @proton_contract.command(
    "ping",
  )
  let request = PingRequest::{ value: "hello", }
  let command = invoke(
    ping,
    request,
    reply => {
      ignore(reply.value)
      @cmd.none
    },
    _error => @cmd.none,
  )
  ignore(command)
}
```

## Ownership and request effects

subscribe creates a description with no installation side effects. Rabbita
installs it in the owning state scope; each installed listener has independent
callbacks and cleanup. Use different key values for multiple subscriptions to
the same event within one scope. Increase retry to explicitly retry an
installation failure. The optional ready command runs after successful listener
installation, so initial queries need not race subscription setup.

For reads tied to component/query lifetime, the default scaffold uses its
application-local internal/query module. It accepts a typed command, initial
input, and an optional invalidation event. Request generations, readiness,
cancellation, and stale completion guards are implementation details of that
module, not parameters that every application model must maintain.

invoke remains a one-shot effect, suitable for explicit writes; it is not
cancelled when a component is removed. Cancelling observation does not roll back
backend mutations. invoke and subscribe accept an optional client for isolated
tests or browser previews.

The Todo scaffold demonstrates explicit backend bindings, typed business
outcomes, managed queries, and separately owned window event destinations.
