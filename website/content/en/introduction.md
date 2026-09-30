# Introduction

Proton is a desktop application framework with a native MoonBit host and a Chromium frontend. Applications can use HTML/JavaScript or a MoonBit frontend compiled to JavaScript. The public application API is `moonbit-community/proton`.

This documentation describes published **Proton 0.3.4**. The CLI and `proton_*` modules share this release version.


## Platform scope

Supported development targets are macOS Apple Silicon, Windows x64 and Linux x64. Native capability availability varies by platform. Builds and packages are produced on their target operating system.

Distributed applications include Chromium and the matching subprocess helper. Runtime size and subprocesses are part of this model; Proton does not use the system webview.

## API references

- [Application API](https://mooncakes.io/docs/moonbit-community/proton@0.3.4/)
- [Extension API](https://mooncakes.io/docs/moonbit-community/proton_ext@0.3.4/)
- [Typed contracts](https://mooncakes.io/docs/moonbit-community/proton_contract@0.3.4/)
- [Frontend client](https://mooncakes.io/docs/moonbit-community/proton_client@0.3.4/)
- [Rabbita integration](https://mooncakes.io/docs/moonbit-community/proton_rabbita@0.3.4/)

Generated API documentation provides full signatures; these reference pages describe behavior and relationships between APIs.

Use the [application API reference index](introduction/application-api.md) to locate behavior by object and lifecycle.
