# proton_cli/codegen

Build-time command/event code generation helpers for the Proton CLI.

This package owns the `#proton.command` and `#proton.event` parser, validation,
and MoonBit source renderer used by the `proton` CLI.

Run command/event code generation with:

```sh
moon -C cli run . --target native -- codegen <input.mbt> -o <output.g.mbt>
moonfmt -w <output.g.mbt>
```

The generator reads `extension.json` from the same package directory as
`<input.mbt>`. The metadata file must contain `id`; `namespace` is optional and
is inferred from the id when absent.

The generator treats `<input.mbt>` as the target file and scans ordinary `.mbt`
files in the same package as context. It ignores `.g.mbt`, `_test.mbt`, and
`_wbtest.mbt` files. Annotated commands/events in the input file are emitted
into a generated `extension()` function returning
`@proton_extension.Extension`; sibling files are used for package-level
duplicate-name checks. The generated command spec is private implementation
detail.

Generated event helpers are async and take an explicit
`context : @proton_command.AppCommandExtensionContext` parameter. Commands only need a
context parameter when they call generated event helpers.

`#proton.script` can annotate a synchronous zero-argument function returning
`String`; generated specs include each returned string in `scripts=[...]`.

`#proton.destroy` can annotate one synchronous function returning `Unit`. The
function may either take no parameters or take
`context : @proton_command.AppCommandExtensionContext`; generated specs wire it to the
command extension destroy hook.
