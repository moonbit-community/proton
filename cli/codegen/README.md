# proton_cli/codegen

`justjavac/proton_cli/codegen` generates a typed command registrar from explicit
MoonBit source inputs.

Each handler binds to a local typed descriptor:

```moonbit
let create_todo_command = @shared.create_todo

#proton.command(contract=create_todo_command)
async fn create_todo(request : @shared.CreateTodoRequest) -> @shared.Todo {
  // ...
}
```

Run codegen with:

```sh
proton_cli codegen <input.mbt>... -o <output.g.mbt>
moonfmt -w <output.g.mbt>
```

All input files must belong to one MoonBit package. When that package contains
`moon.ext`, the generated registrar also exposes its command routes.

Generate the target-neutral contract identity separately from the same metadata:

```sh
proton_cli codegen --extension-identity moon.ext \
  --identity-name extension \
  -o contract/extension_identity.g.mbt
```

Commands and events remain ordinary values in target-neutral MoonBit contract
packages. Extension scripts and destroy hooks are configured explicitly when
constructing the extension.
