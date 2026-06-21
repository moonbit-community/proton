# proton_cli/codegen

`justjavac/proton_cli/codegen` generates Proton command extensions from
MoonBit attributes.

It handles:

- `#proton.command`
- `#proton.event`
- `#proton.script`
- `#proton.destroy`

Run codegen with:

```sh
moon -C cli run . --target native -- codegen <input.mbt> -o <output.g.mbt>
moonfmt -w <output.g.mbt>
```

The input package must contain `moon.ext` with `id` and `namespace`. The
generator emits an `extension()` function and uses sibling `.mbt` files only for
package-level validation.
