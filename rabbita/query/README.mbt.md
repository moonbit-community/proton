# Proton Rabbita queries

`moonbit-community/proton_rabbita/query` is a public JavaScript package released
with Proton. It owns component-scoped reads, cancellation, invalidation and
presentation state. Applications own drafts, write commands, business errors,
and the choice of which events invalidate a read. The public API is versioned
with Proton; review release notes when upgrading.

Import it in the consuming `moon.pkg`:

```moonbit nocheck
///|
import {
  "moonbit-community/proton_rabbita/query",
}
```

Create one query while building a Rabbita component:

```moonbit nocheck
///|
let todos = @query.create(
  @shared.list_todos,
  initial={ query: "", },
  invalidated_by=@shared.todos_changed,
)
```

A query with no invalidation event is just:

```moonbit nocheck
///|
let directory = @query.create(@shared.list_directory, initial="alpha")
```

The command determines input and result types. Pass `client=...` to use an
independent client in a test or browser preview; otherwise the desktop client
is used. Typed invocation, event decoding, cancellation and cleanup are internal.

- `state` is a Rabbita value containing `Loading`, `Ready`, or `Failed`.
- `set_input(value)` returns a command. A different input cancels/replaces the
  current read. The same input does nothing; use `refresh` to explicitly retry.
- `refresh` returns a command that reloads the current input, or retries event
  subscription if it failed. Failures do not create automatic retry loops.
- The optional event subscription is installed before the first read. Event
  payloads are decoded, then treated as invalidation notices, not query results.
  Subscription/decoding failures suspend reads until explicit refresh.
- Completion is accepted once; late callbacks and queued results from
  superseded generations are ignored.
- Query destruction releases its listener and cancels a pending read.

`Loading` and `Failed` can retain `(input, value)` from the last successful read.
`state.input()` is the requested input; `state.data()` retains the original input
of displayed data. A directory view should label that original path while a new
path is loading. Empty successful results are `Ready`, never inferred from an
error or absence of data. Application write errors are kept separately so a
background read cannot erase them. Cancellation stops observing a read; it does
not undo backend work. Use the one-shot `proton_rabbita.invoke` effect for writes.

Invalidations during a read coalesce into one follow-up after success. A failed
read stops and waits for refresh, changed input, or a later invalidation. There
is no cache shared between queries, implicit dependency tracking, background
retry policy, or business-version ordering. The application decides what to
invalidate and where to deliver events; notifications remain best effort.

The explicit input command is intentional: Rabbita's current
`create_state_with_input` does not refresh subscriptions when its input alone
changes. Do not conceal that limitation with side effects in a render function.

## Migrate an existing isomorphic application

This package is introduced after Proton 0.5.0. Upgrade `proton_rabbita` to a
release containing it before removing the application's copy.

1. Review custom changes to `frontend/internal/query`; keep application-specific
   behavior in the application and check it against the contract above.
2. Replace the local query import in each consuming `moon.pkg` with
   `"moonbit-community/proton_rabbita/query"`. The default alias stays `@query`,
   so `create`, `state`, `set_input`, `refresh` and state pattern matches keep
   their existing form.
3. Remove the old query package after all consumers use the shared package.
   Keep application-specific tests; generic query regressions are maintained
   with this package.
4. Run frontend checks and tests, then verify input changes, refresh,
   invalidation and component removal in the application.
