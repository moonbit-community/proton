# Introduction

Proton is a desktop application framework with a native MoonBit host and a Chromium frontend. Applications can use HTML/JavaScript or a MoonBit frontend compiled to JavaScript. The public application API is `moonbit-community/proton`.

This documentation describes published **Proton 0.3.3**. The CLI and `proton_*` modules share this release version.

## Chapters

| Chapter | Contents |
| --- | --- |
| Introduction | Architecture, requirements, project structure and application API concepts |
| <a href='/proton/tutorial/index.html'>Tutorial</a> | Start with minimal, then develop a complete isomorphic Todo application |
| <a href='/proton/command-line-interface/index.html'>Command Line Interface</a> | Every command, option, default and exit status |
| <a href='/proton/configuration/index.html'>Configuration</a> | Every field in `proton.project.json`, including platform overrides |
| <a href='/proton/examples/index.html'>Examples</a> | Ten selected source examples with behavior and limitations |
| <a href='/proton/release-notes/index.html'>Release Notes</a> | Changes in published releases |

## Platform scope

Supported development targets are macOS Apple Silicon, Windows x64 and Linux x64. Native capability availability varies by platform. Builds and packages are produced on their target operating system.

Distributed applications include Chromium and the matching subprocess helper. Runtime size and subprocesses are part of this model; Proton does not use the system webview.

## API references

- [Application API](https://mooncakes.io/docs/moonbit-community/proton@0.3.3/)
- [Extension API](https://mooncakes.io/docs/moonbit-community/proton_ext@0.3.3/)
- [Typed contracts](https://mooncakes.io/docs/moonbit-community/proton_contract@0.3.3/)
- [Frontend client](https://mooncakes.io/docs/moonbit-community/proton_client@0.3.3/)
- [Rabbita integration](https://mooncakes.io/docs/moonbit-community/proton_rabbita@0.3.3/)

Generated API documentation provides full signatures; these reference pages describe behavior and relationships between APIs.
