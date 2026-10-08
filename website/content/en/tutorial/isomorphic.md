# Build a complete Todo application

This tutorial uses the isomorphic template to connect a shared contract, native state, and a Rabbita UI. You will first run the generated Todo app, then add **Complete all** and **Reopen all** operations across all three modules.

Complete [prerequisites](../introduction/installation.md), including Node.js for Warren's build tooling. You do not need to modify the earlier minimal app.

## Create and explore the app

From outside another MoonBit workspace:

```sh
proton_cli new todo-app --template isomorphic --yes
cd todo-app
moon update
moon install moonbit-community/warren@0.3.3
proton_cli cef setup
```

The generated configuration already invokes the installed Warren executable. Start the application:

```sh
proton_cli dev
```

Add “Alpha” and “Beta”, mark one complete, and search for it. The generated app already supports create, complete, delete, and filtered queries. It keeps the list in memory, so restarting clears the data.

Close the application before editing. Keep the generated module names and package imports; all changes below extend the existing template.

## Template organization

The `isomorphic` template has three modules connected by a workspace:

```text
todo-app/
  moon.work
  proton.project.json
  shared/
    moon.mod
    moon.pkg
    todo_contract.mbt
  backend/
    moon.mod
    app/
      moon.pkg
      main.mbt
    todo/
      moon.pkg
      backend.mbt
      commands.mbt
  frontend/
    moon.mod
    main/
      moon.pkg
      main.mbt
    internal/query/
    public/
```

The root `moon.work` connects three modules:

- **shared** defines serializable payloads and command/event descriptors. It is used by both build targets.
- **backend** builds to native code. `todo/backend.mbt` holds Todo state and operations; `todo/commands.mbt` binds those operations; `app/main.mbt` starts the app.
- **frontend** builds to JavaScript. `main/main.mbt` defines the Rabbita UI; `public/` contains its HTML and stylesheet.

The template's `frontend/internal/query` manages query state and subscriptions. It belongs to the generated application and can be changed with it; it is not a public Proton API.

Application commands use ordinary bind calls; this template requires no command code-generation rule.

## Understand the existing flow

For an existing create action, `Create` invokes `create_todo`; the backend validates and mutates; `MutationReply` reports success or a business rejection. `todos_changed` invalidates the frontend snapshot and triggers a query.

The frontend's draft is local UI state. The backend list is authoritative application state. The new action must mutate the full backend list, not just the rows currently visible under a search filter.

## 1. Extend the shared contract

Append to **`shared/todo_contract.mbt`**:

```moonbit
///|
pub(all) struct SetAllCompletedRequest {
  completed : Bool
} derive(ToJson, FromJson)

///|
pub extend SetAllCompletedRequest with ToJson::{to_json}

///|
pub extend SetAllCompletedRequest with FromJson::{from_json}

///|
pub let set_all_completed : @proton_contract.Command[
  SetAllCompletedRequest,
  MutationReply,
] = @proton_contract.command("set_all_completed")
```

The boolean chooses completion or reopening. We reuse the template's `MutationReply`, so the existing response handling remains useful. Both targets import this same descriptor.

## 2. Implement the state change

Append to **`backend/todo/backend.mbt`**:

```moonbit
///|
fn Backend::set_all_completed(
  self : Backend,
  completed : Bool,
) -> @shared.MutationReply {
  let mut changed = false
  for index = 0; index < self.todos.length(); index = index + 1 {
    let todo = self.todos[index]
    if todo.completed != completed {
      self.todos[index] = { ..todo, completed, }
      changed = true
    }
  }
  if changed {
    self.version += 1
  }
  @shared.Changed(version=self.version)
}
```

This operation traverses the full list and advances the revision once if anything changed. Repeating the same operation leaves the revision unchanged. It returns the current version even for an empty list.

## 3. Register the handler and send invalidation

Inside the existing **`Backend::register_commands`** method in **`backend/todo/commands.mbt`**, add another binding beside the existing bindings:

```moonbit
registrar.bind(@shared.set_all_completed, (_context, request) => {
  let reply = self.set_all_completed(request.completed)
  self.notify(reply)
  reply
})
```

Keep the old bindings. `self.notify` is the generated backend's existing helper: it sends `todos_changed` to the event destinations attached by the app's window lifecycle.

No new event type is needed. The state changed in the same way as another Todo mutation, so existing observers should refetch the same query.

## 4. Connect the frontend action

All changes in this step are in **`frontend/main/main.mbt`**.

Add one variant inside the existing `enum Msg`:

```moonbit
SetAllCompleted(Bool)
```

Add this arm inside `update`'s existing `match msg`:

```moonbit
SetAllCompleted(completed) =>
  (
    { ..model, error: None, },
    @proton_rabbita.invoke(
      @shared.set_all_completed,
      { completed, },
      reply => emit(MutationReceived(reply)),
      error => emit(CommandFailed(error)),
    ),
  )
```

`model`, `emit`, `MutationReceived`, and `CommandFailed` already exist in this function and module. The success path reuses the template's mutation response handling; the error path keeps bridge failures visible.

Inside `view`, find `div(class="todo-toolbar", [...])`. Append these two buttons to its child array, after the existing Refresh button:

```moonbit
button(
  type_="button",
  on_click=emit(SetAllCompleted(true)),
  "Complete all",
),
button(
  type_="button",
  on_click=emit(SetAllCompleted(false)),
  "Reopen all",
),
```

The template already imports `button`, so no new import is needed. The boolean in the message travels through the request to the backend.

## 5. Check the behavior

Append this regression check to **`backend/todo/backend_wbtest.mbt`**:

```moonbit
///|
test "bulk completion changes the whole list once" {
  let backend = Backend()
  ignore(backend.create("Alpha"))
  ignore(backend.create("Beta"))
  assert_true(backend.set_all_completed(true) is @shared.Changed(version=3))
  assert_true(backend.snapshot("").todos.all(todo => todo.completed))
  assert_true(backend.set_all_completed(true) is @shared.Changed(version=3))
  assert_true(backend.set_all_completed(false) is @shared.Changed(version=4))
  assert_true(backend.snapshot("").todos.all(todo => !todo.completed))
}
```

From the project root:

```sh
moon check --target js,native
moon -C backend test todo --target native
moon -C frontend test --target js
proton_cli dev
```

Add two todos. **Complete all** should complete both, and **Reopen all** should reopen both. Search for only one todo and repeat the operation, then clear the filter: both items should have changed. Repeating Complete all should not advance the revision again.

If the backend changes but the display does not, check that you retained `self.notify` and the window attach/detach hooks. If the new command is unavailable, check its registration and restart the backend.

## How the UI stays current

The template's `todo_app` creates a query for `list_todos` invalidated by `todos_changed`. Its application-local query helper subscribes before fetching and cancels superseded requests when input changes.

The mutation response refreshes the initiating UI; the event invalidates observers. These can overlap, so the helper tracks request generations and avoids letting an older result overwrite a newer search. This is application code in `frontend/internal/query`, not another server or a public Proton state-management framework.

## Build the finished application

Stop development and run `proton_cli build`. Choose the following branch for your host OS. Run packaging commands from the todo-app project root.

### macOS and Windows

For local acceptance, create an unsigned app artifact. On Windows, app means a directory containing the EXE and its dependencies, not a macOS bundle.

```sh
proton_cli package --release --format app --dry-run
proton_cli package --release --format app
```

Open the artifact path printed by the CLI under dist: the .app on macOS, or the application EXE inside the Windows output directory. Do not copy the EXE alone. This step needs no NSIS and does not perform distribution signing or notarization.

### Linux

The default template supplies no icon. Save a valid PNG icon as `icons/app.png` inside the project and add this field to the existing package object in proton.project.json:

```json
"icons": ["icons/app.png"]
```

Check that `appimagetool --version` runs. If necessary, install it in your user directory from an Ubuntu x64 shell. Extracting the packaging tool avoids requiring FUSE to run it:

```sh
mkdir -p "$HOME/.local/lib/proton-appimagetool"
cd "$HOME/.local/lib/proton-appimagetool"
curl -fL -o tool.AppImage https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage
echo 'ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0  tool.AppImage' | sha256sum -c -
chmod +x tool.AppImage
./tool.AppImage --appimage-extract
ln -sf squashfs-root/AppRun appimagetool
export PATH="$HOME/.local/lib/proton-appimagetool:$PATH"
appimagetool --version
```

Return to the todo-app project root, then run:

```sh
proton_cli package --release --format appimage --dry-run
proton_cli package --release --format appimage
```

Launch the output AppImage in a graphical session. If the runtime environment cannot mount AppImages, run the artifact with `--appimage-extract` and launch AppRun inside the extracted directory.

### Acceptance

With the development server stopped, launch the artifact, add two items, and verify Complete all, Reopen all, and search. Packaging failure, launch failure, and incorrect button behavior are separate stages; dry-run alone is not acceptance.

The list is intentionally in memory and resets on restart. Implement persistence in the backend. See [packaging reference](../command-line-interface/packaging.md) for icons and distribution requirements.
