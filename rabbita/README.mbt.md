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

An event subscription installation failure is reported through its failure
callback once. Rabbita retains a terminal subscription for that key instead of
retrying after every model update, which prevents a failure-message feedback
loop. To retry explicitly, omit the subscription for one update and then add it
again. The Proton bridge is expected to be available before application
frontend code starts.
