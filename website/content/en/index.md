# Build desktop applications with MoonBit

[中文](zh/index.html)

Proton combines a native MoonBit backend with a Chromium web frontend. You can start with plain HTML or use Rabbita to write both sides in MoonBit.

[Get started →](installation.md) · [Build the Todo example](isomorphic.md)

```moonbit
async fn main {
  @proton.html("Hello Proton", "<h1>Hello from MoonBit</h1>")
  .load_config()
  .run_or_abort()
}
```

This entry runs inside a generated minimal project. [Create a project](first-app.md) supplies the package imports, dependencies, and application identity.

## Why Proton?

Write application logic and native integrations in MoonBit, render your interface with web technologies, and communicate through commands and events. With the isomorphic template, the backend and Rabbita frontend share MoonBit request and response types.

Proton bundles the Chromium runtime with distributed applications. This gives the frontend a Chromium environment on each supported platform, with the corresponding runtime size and subprocesses. It does not use the operating system's installed webview.

## Choose a starting point

- **New to Proton:** prepare your environment, [create a minimal app](first-app.md), then understand its [project structure](project-structure.md).
- **Adding a feature:** learn to [call the backend](commands-events.md), [send events](events.md), or [access native capabilities](capabilities.md).
- **Writing both sides in MoonBit:** follow the [complete Todo example](isomorphic.md) using the isomorphic template.
- **Ready to ship:** [build and distribute](packaging.md) an application.

The [architecture guide](architecture.md) explains where your code runs and which state belongs on each side.

## Supported platforms

Proton 0.2.11 supports macOS on Apple Silicon, Windows x64, and Linux x64. Build and package on the target operating system. Individual native capabilities can have narrower platform support.

These guides assume basic MoonBit knowledge and cover the published **0.2.11** release. Keep the CLI and Proton packages on that version while following the examples.

## Reference

Use the [Proton API](https://mooncakes.io/docs/moonbit-community/proton@0.2.11/) and [extensions API](https://mooncakes.io/docs/moonbit-community/proton_ext@0.2.11/) for signatures and available options. The [repository example catalog](https://github.com/moonbit-community/proton/blob/main/examples/Readme.md) provides focused demonstrations; it follows main and may include unreleased changes.
