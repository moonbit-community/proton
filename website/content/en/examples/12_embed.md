# Embedded HTML

[中文](../zh/examples/12_embed.html)

HTML stored as a source asset and embedded into a MoonBit string.

[12_embed](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/12_embed) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/12_embed/main.mbt), [hello.html](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/12_embed/hello.html), [hello.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/12_embed/hello.mbt), [moon.pkg](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/12_embed/moon.pkg)

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

[Environment requirements](../installation.md) apply. From the checked-out repository root:

```sh
moon -C examples run 12_embed --target native
```

## Limits and interpretation

Edit hello.html, not generated hello.mbt. Embedded HTML does not automatically include sibling files; use the sidecar example for separate JS/CSS.
