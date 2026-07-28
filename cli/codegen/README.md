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
`moon.ext`, the generated file also exposes its extension identity. Commands
and events remain ordinary values in target-neutral MoonBit contract packages;
extension scripts and destroy hooks are configured explicitly when constructing
the extension.
