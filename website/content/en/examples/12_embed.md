# Embedded HTML

HTML stored as a source asset and embedded into a MoonBit string.

[12_embed](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/12_embed) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/12_embed/main.mbt), [hello.html](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/12_embed/hello.html), [hello.mbt](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/12_embed/hello.mbt), [moon.pkg](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/12_embed/moon.pkg)

## Behavior

The window loads the embedded resource through html(). The package prebuild rule produces hello.mbt from hello.html.

```moonbit
///|
async fn main {
  @proton.html("12 embed", resource, width=800, height=600, debug=true)
  .identifier("dev.proton.12-embed")
  .run_or_abort()
}
```

## Run

[Environment requirements](../introduction/installation.md) apply. From the checked-out repository root:

```sh
moon -C examples run 12_embed --target native
```

## Limits and interpretation

Edit hello.html, not generated hello.mbt. Embedded HTML does not automatically include sibling files; use the sidecar example for separate JS/CSS.

## Key code and design

`resource` is generated from hello.html by the package's embed prebuild rule. The runtime receives the same kind of string as the minimal example; it does not read hello.html from disk at launch.

Edit hello.html and rebuild. Do not edit generated hello.mbt. Embedding a document does not automatically embed every relative image or script it references; use an asset entry for a directory of resources.
