# Proton Contract

`justjavac/proton_contract` defines target-neutral typed command and event
descriptors shared by Proton frontends and backends.

Application contracts use explicit stable identities:

```moonbit nocheck
///|
pub let create_todo : @proton_contract.Command[CreateTodoRequest, Todo] = @proton_contract.command(
  "create_todo",
)

///|
pub let todo_changed : @proton_contract.Event[TodoChanged] = @proton_contract.event(
  "todo_changed",
)
```

Each event route is declared exactly once within its scope. Put event
descriptors in a shared contract package and import those values from both the
frontend and backend. Constructing another event descriptor with the same route
is rejected, even when it repeats the same payload type. Runtime identifiers and
other varying data belong in event payloads, not in dynamically constructed
route names.

The descriptors do not own serialization. Frontend and backend integrations
apply the appropriate `ToJson` and `FromJson` constraints when a descriptor is
used.
