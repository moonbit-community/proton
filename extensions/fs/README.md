# FS Extension

`justjavac/proton_ext/fs` contains a thin command-extension wrapper around
`moonbitlang/async/fs`.

It is exposed as an app command extension, so filesystem calls run through the
same async command bridge used by the other native Proton extensions.

## Scope

- MoonBit-style operation names such as `read_file`, `write_file`, `mkdir`,
  `readdir`, `remove`, `rmdir`, `rename`, `realpath`, `exists`, `kind`, and
  `size`.
- Activity event metadata.
- Metadata used by catalog and code generation checks.

Keep new operations close to the shape of `moonbitlang/async/fs` and avoid
adding JavaScript helpers or hand-rolled filesystem behavior.

## Safety Notes

- This extension grants direct host filesystem access when eventually exposed.
- Use it only with trusted local HTML/JavaScript.
- Text helpers use UTF-8 payloads.
