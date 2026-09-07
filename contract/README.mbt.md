# Proton Contract

`moonbit-community/proton_contract` defines target-neutral typed command and event
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

Descriptors are inert values. Reconstructing an event does not register a
listener or mutate process state. Keep shared route and payload definitions in
one contract package so independently compiled frontends and backends agree.
Command binding and extension event-source installation reject conflicting
registrations in their owning runtime; descriptors do not prove that a remote
handler is installed or authorized.

Use a response enum for expected business outcomes (for example Created,
InvalidTitle, or MissingTodo). Transport and unexpected execution failures
remain client failures. Runtime identifiers belong in payloads rather than
dynamically generated route names.

The descriptors do not own serialization. Frontend and backend integrations
apply the appropriate `ToJson` and `FromJson` constraints when a descriptor is
used.

The former DuplicateEventRoute definition error has been removed. Applications
that matched that variant should remove that branch; repeated descriptor
construction is now valid. Existing command and event route names are unchanged.
