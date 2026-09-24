# Commands

A command is a typed request/response operation across the renderer–host boundary. Payloads are serialized; a shared MoonBit type does not share memory or execute backend code in the renderer.

## Contract and binding

| API | Contract |
| --- | --- |
| `proton_contract.command[Request, Response](name)` | Declares a typed application route; does not register a handler |
| `App.commands(register, targets?)` | Installs application command bindings for selected renderer targets |
| `CommandRegistrar.bind(command, handler)` | Binds an async handler taking `(CommandContext, Request)` and returning `Response` |
| `proton_client.invoke(command, request)` | Async frontend invocation; returns `Response` or raises `ClientFailure` |
| `proton_rabbita.invoke(...)` | Adapts completion/failure to Rabbita commands |

On the backend, `Request` must implement `FromJson` and `Response` must implement `ToJson`. The frontend requires the inverse conversions. Contract and registration errors are distinct from failures of a running request. Application route names must be unique and valid; descriptors are validated during binding and invocation.

The handler context identifies the caller and supports `emit_to_caller`. A handler may await backend work. Business outcomes such as validation rejection can be modeled in the response type rather than thrown as transport failures.

## JavaScript interface

The injected bridge exposes application methods as `window.__MoonBit__.app.<name>(request)`. Calls return promises; failures reject them. Application routes use `app:`; extension operations use `ext:`. An ordinary browser page has no injected native bridge.

## Payload size

Proton does not impose a fixed payload-size limit on commands. Payloads are serialized as JSON and remain subject to memory and underlying transport constraints. Large messages increase serialization, copying and parsing costs.

## Cancellation

`proton_client.invoke_with_callbacks` returns a cancellation function. It cancels response observation and requests transport cancellation; late responses are ignored. Async `invoke` also cancels the pending request when its task is cancelled. Cancellation is not a rollback guarantee for work already performed by the backend.

## Client failures

| Variant | Meaning |
| --- | --- |
| `BridgeUnavailable` | Native bridge is absent |
| `InvalidContract` | Invalid command/event descriptor |
| `RemoteFailure` | Backend rejection with code, message and optional detail |
| `TransportFailure` | Communication failure |
| `ResponseDecode` | Response does not decode as the declared type |
| `RequestCancelled` | The pending request was cancelled |

Commands provide responses to their callers. [Events](events.md) provide notifications to observers; neither implies durable application storage.

See [API signatures](https://mooncakes.io/docs/moonbit-community/proton_client@0.3.3/) and the separate [command tutorial](../tutorial/commands-events.md).

### Command error codes

`RemoteFailure.code` identifies the failure independently of its message:

| Code | Meaning |
| --- | --- |
| `invalid_payload` | The request does not match the command's input type |
| `unknown_op` | The requested operation is not registered |
| `handler_failed` | The command handler raised an error |
| `host_closed` | The command host has closed |
| `permission_denied` | The page is not permitted to invoke the operation |

Handle codes rather than parsing message text, and handle unrecognized codes as
other remote failures. Backend diagnostics remain in application logs. Development mode
also includes them in `detail`; `message` remains
a caller-facing description. Expected business outcomes belong in the command's
response type.
