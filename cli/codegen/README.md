# lepus_cli/codegen

Build-time command/event code generation helpers for the Lepus CLI.

This package owns the `#lepus.command` and `#lepus.event` parser, validation,
and MoonBit source renderer used by the `lepus` CLI.

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
into a generated `AppCommandExtensionSpec`; sibling files are used for
package-level duplicate-name checks.

Generated event helpers are async and take an explicit
`context : @app.AppCommandExtensionContext` parameter. Commands only need a
context parameter when they call generated event helpers.

`#lepus.script` can annotate a synchronous zero-argument function returning
`String`; generated specs include each returned string in `scripts=[...]`.

`#lepus.destroy` can annotate one synchronous function returning `Unit`. The
function may either take no parameters or take
`context : @app.AppCommandExtensionContext`; generated specs wire it to the
command extension destroy hook.
