# Typed Isomorphic Proton Implementation Plan

This is a temporary execution document for one pull request. Each numbered
phase ends in its own commit and must leave the repository buildable. Once all
phases and final validation pass, delete this file and `CONTEXT.md` in the last
commit of the pull request.

## Objective

Replace Proton's string-oriented application bridge and extension-shaped
application backend with a typed, target-neutral contract model shared by a
Rabbita frontend and a Proton backend. Add a framework-neutral async client, a
Rabbita adapter, structured lifecycle ownership through MoonBit task groups,
and a three-module isomorphic default scaffold.

## Constraints

- Use one pull request and one commit per completed phase.
- Do not keep compatibility APIs or parallel runtime routes.
- Do not add a second scheduler, event loop, task abstraction, or browser
  fallback backend.
- Preserve the supported ordinary JavaScript bridge API over the same
  transport.
- Keep `moon.ext` as the source of extension-level static metadata.
- Keep command and event schemas exclusively in MoonBit contracts.
- Keep generated source committed for published packages, but let application
  packages generate their own bindings through user-authored `dev_build`
  declarations.
- Do not merge a phase until its focused tests pass.

## Target Repository Modules

Add these framework modules to `moon.work`:

```text
contract/  -> justjavac/proton_contract
client/    -> justjavac/proton_client
rabbita/   -> justjavac/proton_rabbita
```

Existing responsibilities remain:

```text
proton/      native backend runtime and public application facade
extensions/  extension implementations and target-neutral contract packages
cli/         project orchestration, code generation, doctor, and scaffolding
native/      C ABI and platform engine implementation
```

Dependency direction:

```text
proton_client  -> proton_contract
proton_rabbita -> proton_client + proton_contract + Rabbita
proton         -> proton_contract
frontend app   -> shared app contract + proton_rabbita
backend app    -> shared app contract + proton
```

`proton_contract` must compile on every target and must not depend on Rabbita,
JavaScript, the native runtime, or an extension implementation.

## Public API Shape

### Contracts

Application contracts are ordinary MoonBit values with explicit stable names:

```moonbit
pub let create_todo : @proton_contract.Command[
  CreateTodoRequest,
  TodoSnapshot,
] = @proton_contract.command("create_todo")

pub let todos_changed : @proton_contract.Event[TodoSnapshot] =
  @proton_contract.event("todos_changed")
```

`Command[Request, Response]` and `Event[Payload]` carry an opaque application or
extension route. They do not store codecs. Codec constraints are applied where
the descriptor is invoked, bound, subscribed, or emitted. Scaffold payload
types derive both `ToJson` and `FromJson` for convenience.

Extension contracts use the same descriptor types:

```moonbit
pub let extension : @proton_contract.ExtensionContract = generated_extension
pub let open_file = extension.command("open_file")
```

`moon.ext` owns extension identity, package, platform, and dependency metadata.
It does not list commands or events. Generated extension identity source is
committed and checked by `scripts/verify_generated.mjs`.

### Backend Binding

Code generation accepts one or more explicit MoonBit inputs and emits one
package registrar:

```moonbit
dev_build(
  rule: "proton_codegen",
  input: ["todo.mbt", "workspace.mbt"],
  output: "commands.g.mbt",
)
```

No directory scanning or handler filename convention is allowed.

Annotations bind handlers to shared descriptors:

```moonbit
#proton.command(contract=@shared.create_todo)
async fn Backend::create_todo(
  self : Backend,
  context : @proton.CommandContext,
  request : @shared.CreateTodoRequest,
) -> @shared.TodoSnapshot {
  ...
}
```

Support both stateless free functions and stateful receiver methods:

```moonbit
pub fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise
pub fn Backend::register_commands(
  self : Backend,
  registrar : @proton.CommandRegistrar,
) -> Unit raise
```

The descriptor remains the only command identity. A receiver does not add a
service or namespace. Delete `#proton.event`, generated event helpers,
`emits_events`, and string-based command annotation options.

### Frontend Client

The current renderer supplies one implicit current-page bridge capability.
Application code does not construct or pass client instances.

```moonbit
pub async fn[Request : ToJson, Response : FromJson] invoke(
  command : @proton_contract.Command[Request, Response],
  request : Request,
) -> Response raise ClientFailure
```

The JavaScript bootstrap exposes raw JSON text primitives for MoonBit:

```text
invokeJson(route, requestJson, options?) -> Promise<responseJson>
events.onJson(route, listener) -> unsubscribe
```

The existing JavaScript object API remains supported and uses the same pending
request table, event dispatcher, structured errors, and transport.

`ProtonBridgeError` carries a stable code and message. Development mode may
include diagnostic detail; production mode logs full backend detail without
exposing internal paths or stacks to the frontend.

Caller cancellation removes renderer pending state and ignores a late reply. It
does not promise to stop or roll back backend side effects. Lifecycle
cancellation is separate and terminates the backend tasks owned by the closing
window or application.

### Rabbita Adapter

`proton_rabbita` owns no serialization or transport:

```moonbit
pub fn invoke(
  command,
  request,
  success : Response -> @rabbita.Cmd,
  failure : @proton_client.ClientFailure -> @rabbita.Cmd,
) -> @rabbita.Cmd

pub fn subscribe(
  event,
  received : Payload -> @rabbita.Cmd,
  failure : @proton_client.ClientFailure -> @rabbita.Cmd,
) -> @sub.Sub
```

Do not expose a `Result` callback. A malformed event reports one failure while
the live subscription remains installed. Subscription unload removes the
bridge listener, and tagger updates do not reinstall it.

Opening the Warren page in an ordinary browser fails immediately with
`BridgeUnavailable`. Fake transport injection is package-private test support,
not a production fallback.

## Lifecycle Model

Application lifecycle contains zero or more window lifecycles. Each lifecycle
uses the official MoonBit `@async.TaskGroup` directly:

```text
Application TaskGroup
├── Window A TaskGroup
│   ├── Command TaskGroup
│   └── window-owned background tasks
├── Window B TaskGroup
└── application-owned background tasks
```

`ApplicationContext`, `WindowContext`, and `CommandContext` provide their
official task group to backend code. Proton must not wrap `TaskGroup` or
duplicate `async/process` and other downstream APIs.

Application and window lifecycle hooks are paired and stateful:

```moonbit
.app_lifecycle(on_start=..., on_shutdown=...)
.window_lifecycle(on_ready=..., on_close=...)
```

Each start hook returns its generic state, which is passed to the paired stop
hook. Starts run in registration order; stops and rollback run in reverse order.

Event routing is explicit:

- `CommandContext::emit` targets the page instance that issued the request.
- `WindowEventEmitter::emit` targets the active page of one explicit window.
- There is no process-global event broadcaster or scoped-sender mutex.

Startup order:

1. Construct backend instances and the app configuration on the worker.
2. Create the native runtime.
3. Register and seal all commands.
4. Start application lifecycle hooks.
5. Create a window and install its bridge.
6. Load the frontend and wait for bootstrap readiness.
7. Start that window's lifecycle hooks.
8. Show the window and run the managed pump.

Shutdown order:

1. Stop request admission for the closing page/window.
2. Cancel and join its command tasks.
3. Stop its window lifecycle hooks.
4. At app shutdown, close command admission and cancel/join remaining scopes.
5. Stop application lifecycle hooks.
6. Destroy windows and the native runtime.

Do not add a fixed shutdown timeout and do not shut down CEF while managed tasks
or browser close lifecycle work remains.

## Default Scaffold

`proton new <path>` derives the project short name from the last path segment.
Remove `--module` and do not add `--name`. Add `--author`, defaulting to the
literal string `"username"`.

For `proton new todo`, generate:

```text
username/todo_shared
username/todo_frontend
username/todo_backend
```

Project layout:

```text
todo/
├── moon.work
├── moon.proton
├── README.md
├── AGENTS.md
├── .gitignore
├── shared/
│   ├── moon.mod
│   ├── moon.pkg
│   └── todo_contract.mbt
├── frontend/
│   ├── moon.mod
│   ├── main/
│   │   ├── moon.pkg
│   │   └── main.mbt
│   └── public/
│       ├── index.html
│       └── styles.css
└── backend/
    ├── moon.mod
    ├── app/
    │   ├── moon.pkg
    │   └── main.mbt
    └── todo/
        ├── moon.pkg
        ├── backend.mbt
        ├── commands.mbt
        └── commands.g.mbt
```

The project root is not a fourth MoonBit module. `moon.work` contains the three
module paths.

Project configuration uses `path`, not `cwd`:

```moonbit
backend = {
  path: "backend",
  package: "app",
}

frontend = {
  path: "frontend",
  dev_url: "http://127.0.0.1:4300",
  before_dev: "warren dev --port 4300",
  before_build: "warren build",
  dist: "dist",
}
```

Rename existing `frontend.cwd` to `frontend.path`; do not retain both fields.

The backend module declares `justjavac/proton_cli` as a Moon binary dependency.
Its codegen rule invokes
`$mooncake_bin/proton_cli codegen $input -o $output`, so application builds do
not depend on PATH or a repository-relative CLI.

The generated app is an in-memory Todo application with:

- list, create, complete/uncomplete, and delete commands;
- a versioned `TodoSnapshot`;
- a live `todos_changed` event;
- Rabbita command success and failure paths;
- a live event subscription;
- a clear `BridgeUnavailable` state in an ordinary browser.

Warren owns frontend dev/build behavior. Proton CLI only starts the configured
command, waits for `dev_url`, cleans up the child process, builds the configured
backend package, and stages `frontend.dist`.

## Commit Sequence

### 1. `feat(contract): add typed bridge descriptors`

- Add `justjavac/proton_contract`.
- Implement opaque application and extension routes.
- Add typed command and event descriptors.
- Add extension identity generation from `moon.ext`.
- Add target-neutral route and metadata tests.

Acceptance:

- Contract tests pass on JS and native targets.
- No contract package imports Proton runtime, Rabbita, or platform code.

### 2. `feat(client): add typed async bridge client`

- Add raw JSON bootstrap invocation and event primitives.
- Preserve the existing JavaScript object API over the same dispatcher.
- Add structured bridge error codes and development diagnostics.
- Add cancellation cleanup and late-response suppression.
- Add `justjavac/proton_client` with typed encode/decode.
- Add fake-transport client tests.

Acceptance:

- Success, remote failure, encode/decode failure, timeout, cancellation,
  missing bridge, event decode failure, and listener unload are covered.
- Cancellation leaves no renderer pending request.

### 3. `refactor(commands): generate typed registrars`

- Add `CommandRegistrar`.
- Change `#proton.command` to require an explicit contract expression.
- Support multiple input files, free functions, and receiver methods.
- Make every generated binding use one async dispatch path.
- Remove command names and payload schema synthesis from annotations.
- Remove `#proton.event`, event helper generation, and `emits_events`.

Acceptance:

- Golden codegen tests cover sync/async, context/no-context, free/receiver, and
  multiple input files.
- The MoonBit compiler rejects descriptor/handler request or response mismatch.
- Duplicate application command identities fail startup.

### 4. `refactor(runtime): use structured application lifecycles`

- Add paired application and window lifecycle APIs with generic state.
- Nest official application, window, and command TaskGroups.
- Add application, window, and command contexts.
- Add request-scoped and explicit window-scoped typed event emission.
- Remove process-global sender fallback, scoped event sender, and event mutex.
- Implement transactional startup and reverse-order shutdown.

Acceptance:

- Failed startup rolls back only completed hooks.
- Window close cancels and joins window commands and child processes.
- App shutdown joins all managed work before native runtime destruction.
- Existing close/child-process regression examples terminate without timeout
  fallback or CEF shutdown races.

### 5. `feat(rabbita): add typed Proton effects and subscriptions`

- Add `justjavac/proton_rabbita`.
- Implement command success/failure mapping.
- Implement live subscriptions with stable identity, tagger update, and unload.
- Keep serialization in `proton_client`.
- Add Rabbita adapter tests using public `Cmd`/`Sub` integration points.

Acceptance:

- Commands dispatch exactly one success or failure message.
- Subscription updates do not reinstall listeners.
- Unload removes listeners.
- One malformed event reports failure without terminating the subscription.

### 6. `refactor(extensions): migrate contracts and generated bindings`

- Add a target-neutral contract package for every extension.
- Keep `moon.ext` as extension metadata source.
- Generate and commit extension identity sources.
- Migrate all extension handlers to typed descriptors.
- Migrate extension events to explicit typed emission.
- Remove legacy command/event generation and registration APIs.
- Migrate examples and generated sources.

Use multiple commits within this phase when needed, grouped by extension family;
never leave a commit with both old and new runtime paths active.

Acceptance:

- `scripts/verify_generated.mjs` passes.
- Every extension compiles on each target it declares.
- Existing JavaScript extension facades still invoke the migrated handlers.

### 7. `refactor(config): model frontend and backend module paths`

- Add `backend.path` and `backend.package`.
- Rename `frontend.cwd` to `frontend.path`.
- Update parser, schema, diagnostics, doctor, dev, build, and package workflows.
- Make CLI commands execute relative to the declared module path.

Acceptance:

- Config parsing rejects unknown legacy `cwd`.
- Dev/build/package resolve all paths relative to `moon.proton`.
- CLI focused tests cover nested project roots and paths containing spaces.

### 8. `feat(cli): generate an isomorphic Rabbita Todo app`

- Replace the current single-module counter template.
- Add `--author` and remove `--module`.
- Generate the three-module workspace and Todo implementation.
- Declare the codegen binary dependency and user-owned `dev_build`.
- Keep project creation transactional.
- Update new-project tests, README, and doctor guidance.

Acceptance:

- `proton new` produces exactly the documented tree.
- Default and explicit authors produce correct module names.
- A failed check leaves no partial project.

### 9. `test(e2e): validate the typed isomorphic scaffold`

- Generate a project outside the repository.
- Run checks for all three modules.
- Run Warren release build.
- Run Proton native backend build.
- Run codegen staleness checks.
- Run the app through the managed runtime.
- Exercise all Todo commands and the live event path.
- Verify ordinary-browser startup reports `BridgeUnavailable`.
- Package the app and verify staged frontend assets.

Acceptance:

- Focused module tests, repository checks, generated checks, native tests, and
  scaffold smoke tests pass.
- Manual macOS close confirms no residual process or CEF shutdown crash.

### 10. `chore: remove completed architecture plan`

- Delete `IMPLEMENTATION_PLAN.md`.
- Delete `CONTEXT.md`.
- Run the final validation matrix again after deletion.

## Final Validation Matrix

At minimum, run:

```sh
moon fmt --check
node scripts/verify_generated.mjs
moon check --target native
moon -C contract test --target native
moon -C contract test --target js
moon -C client test --target js
moon -C rabbita test --target js
moon -C proton check --target native --diagnostic-limit 80
moon -C cli test --target native --diagnostic-limit 80
moon -C extensions test --target native
moon -C examples build --target native
moon -C e2e build --target native
```

When native ABI or bridge engine code changes, also run the native CMake/CTest
suite, ABI verification, and relevant bridge smoke scenarios from the
maintainer guide.

The pull request is complete only when the generated Todo project can be
checked, built, run, closed, and packaged without repository-local overrides.
