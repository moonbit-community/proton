# Architecture & processes

Proton combines a native MoonBit application with the Chromium browser engine. The application process manages windows, application state and operating-system features. Web pages provide the interface and invoke host operations through messages.

## Components and responsibilities

| Component | Responsibility |
| --- | --- |
| Native MoonBit application | Runs the application entry point, business logic and asynchronous tasks |
| Proton | Provides APIs for windows, lifecycle, browser contents and frontend/host communication |
| CEF (Chromium Embedded Framework) | Embeds Chromium in the native application, providing browser creation, callbacks and process communication interfaces |
| Chromium | Implements the web platform, including rendering, JavaScript, networking and browser storage |
| Web frontend | Implements the application interface with HTML, CSS and JavaScript |

Applications use the public API in `moonbit-community/proton`. Proton's native bindings are compiled from source into the application; CEF/Chromium is loaded as a separate runtime and bundled for distribution. Pages use that bundled browser engine rather than an operating-system WebView.

The frontend can use ordinary JavaScript or JavaScript produced by the MoonBit compiler. Rabbita is an optional MoonBit UI library; `proton_rabbita` integrates commands and subscriptions with it. Neither is a required part of the Proton runtime.

## Process model

The application executable runs MoonBit host code and hosts CEF's browser process. This process manages native windows and browser instances and coordinates Chromium subprocesses. Page scripts execute in renderer processes; GPU and utility processes provide graphics and other browser services.

```text
Application process
  MoonBit application logic
       |
  Proton -- Native windows
       |
  CEF browser process
       | Chromium inter-process communication
       +-- Renderer processes: pages, JavaScript, workers
       +-- GPU process: graphics
       +-- Utility and other processes: browser services
```

`cef_process` is the helper executable CEF launches for subprocesses. CEF selects the role at launch, so the same helper can serve different subprocess roles. It does not execute the application's MoonBit entry point. The helper matches the application's Proton release and CEF runtime.

Chromium manages process allocation according to pages and runtime state. One renderer can host multiple tasks, such as a page and workers. Window counts, browser-instance counts, task counts and OS process counts therefore do not map one to one. Task resource metrics cannot simply be summed into application-wide usage.

## Windows and browser contents

One Proton application runtime can manage multiple native windows. Each window owns its main browser contents and can host additional child browser views:

```text
Application runtime
  +-- Window A
  |    +-- Main browser contents
  |    +-- Child browser view
  +-- Window B
       +-- Main browser contents
```

A window owns its title, position, dimensions and native decorations. Browser contents own documents, navigation, scripts and page events. A child view is an independent browser within the window's content area, with its own document and bounds. Navigating it does not navigate the main page; removing it does not close the entire window.

These objects have distinct lifetimes: a page can reload or its renderer can terminate while the native window remains alive. Closing a window also closes its hosted browser contents. See the [application API](application-api.md#windows-and-browser-views) for creation, closing and recovery contracts.

## Execution and communication boundaries

Native UI objects are managed by their creating thread. Proton connects native event processing to the `moonbitlang/async` external event loop: native callbacks enqueue records and wake the scheduler, then MoonBit handles events and application callbacks. Asynchronous application tasks can yield execution, but expensive synchronous work still occupies the host event loop.

Renderers and the host have separate execution environments. Proton injects a bridge into pages, delivers frontend requests to registered host handlers and returns their results or errors. The host can also send event notifications. Payloads are serialized; shared type definitions do not create shared memory.

`proton_contract` describes typed commands and events, and `proton_client` supports MoonBit frontend calls. JavaScript frontends use the page bridge directly. Host command bindings and capabilities select which operations are available to which pages. See [commands](application-api.md#commands), [events](application-api.md#events) and [capabilities](application-api.md#extensions-and-capabilities) for protocol, cancellation and authorization behavior.

## Development and distribution

Development and distribution use the same native host and browser architecture. The sources of page content and runtime files change.

| Scenario | Page source | Native runtime source |
| --- | --- | --- |
| Inline HTML | A string compiled into the application | Shared runtime and helper installed by setup |
| Frontend development server | Development URL configured through the CLI | Shared runtime and helper installed by setup |
| Packaged application | Inline content or packaged static resources; URL entries may also use remote pages | Runtime and helper shipped in the artifact |

A frontend development server serves page resources; it does not run host business logic. Opening the same URL in an ordinary browser provides no Proton native bridge. Packaging assembles the application executable, required page resources, CEF runtime and helper into a distributable artifact. See [project structure](project-structure.md) for source layout and build outputs. The Command Line Interface chapter documents packaging formats and requirements.
