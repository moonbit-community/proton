# proton_codegen

`moonbit-community/proton_codegen` is the WASM code generator for typed Proton
command registrars. Run it directly from the Mooncakes registry with `moonx`:

```sh
moonx moonbit-community/proton_codegen@<version> \
  commands.mbt -o commands.g.mbt
```

Proton application packages should declare this invocation as a Moon prebuild
rule so `moon check`, `moon build`, and `moon run` regenerate the registrar from
its explicit inputs.

The library package `moonbit-community/proton_codegen/lib` contains the command
signature reader and renderer used by the executable and by Proton's own tooling.
It uses the MoonBit lexer to find top-level `#proton.command` functions and
validate their parameters. Function bodies and unrelated declarations are not
parsed; the MoonBit compiler remains responsible for complete syntax and type
checking. Code generation does not depend on `moonbitlang/parser` or MoonYacc.
