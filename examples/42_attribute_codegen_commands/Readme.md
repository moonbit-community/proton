# Attribute Codegen Commands

Attribute-codegen command example for the native DLL bridge.

This package uses generated command metadata to expose
`window.__MoonBit__.add.slowAdd(payload)` through the same inline HTML proxy
layer used by the hand-written command examples. It also uses the generated
event helper to emit `add.addFinished` into `window.__MoonBit__.events`.

Build:

```sh
moon -C examples build 42_attribute_codegen_commands --target native
```

E2E:

```sh
node scripts/e2e_bridge_smoke.mjs 42_attribute_codegen_commands
```
