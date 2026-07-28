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

The descriptors do not own serialization. Frontend and backend integrations
apply the appropriate `ToJson` and `FromJson` constraints when a descriptor is
used.
