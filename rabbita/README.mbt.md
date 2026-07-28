# Proton Rabbita

`justjavac/proton_rabbita` maps typed Proton commands and events onto Rabbita
`Cmd` and `Sub` values. Transport and JSON handling remain owned by
`justjavac/proton_client`.

```mbt check
///|
struct PingRequest {
  value : String
} derive(ToJson)

///|
struct PingReply {
  value : String
} derive(FromJson)

///|
test {
  let ping : @proton_contract.Command[PingRequest, PingReply] = @proton_contract.command(
    "ping",
  )
  let request = PingRequest::{ value: "hello" }
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
