# FS Extension

`moonbit-community/proton_ext/fs` contains a thin command-extension wrapper around
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

- Add it with `@fs.capability(...)`; each `PermissionRoot` pairs one host
  directory with the exact filesystem commands allowed below it.
- Permission roots are backend configuration. Renderer requests cannot add or
  widen them.
- Relative permission roots and relative renderer paths are anchored to
  `@proton.resource_dir()`. The CLI supplies the project root during development,
  packaged apps use their resources directory, and direct runs use the startup
  working directory.
- Canonical path checks and filesystem operations are serialized so concurrent
  renderer requests cannot race a path check with a rename.
- A path that resolves outside every matching root is denied, including a
  symbolic-link escape.
- Text helpers use UTF-8 payloads.
