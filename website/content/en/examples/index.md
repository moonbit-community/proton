# Examples

Ten examples selected for focused behavior, readable entry points and coverage of distinct framework features. Source links are pinned to the 0.3.3 release commit so documentation and code stay aligned. These are runnable references; step-by-step application development belongs in [Tutorial](../tutorial/index.md).

| Example | Focus |
| --- | --- |
| [Minimal application](01_run.md) | Inline HTML and a native application entry point. |
| [Embedded HTML](12_embed.md) | HTML stored as a source asset and embedded into a MoonBit string. |
| [Filesystem capability](18_extension_fs.md) | A renderer requests file operations within an explicit permission root. |
| [Typed events](40_event_broadcast.md) | Progress events emitted during an asynchronous command. |
| [Multi-window commands](45_bridge_multi_window.md) | Typed command registration shared by multiple windows. |
| [HTML with sidecar assets](46_asset_sidecar_resources.md) | An asset entry with separate JavaScript, CSS and worker files. |
| [Native application menu](49_app_menu.md) | Typed menus with dynamic command state and application callbacks. |
| [Embedded browser view](53_view_minimal.md) | A declarative child browser alongside a host sidebar. |
| [Application locale](56_i18n.md) | One startup locale observed by commands, Chromium and native menus. |
| [Background residency](57_background_residency.md) | A single-instance app survives closing its last window. |

## Source checkout and runtime

Examples use the repository workspace. Clone the release commit, install the [required tools](../introduction/installation.md), and set up its runtime once:

```sh
git clone https://github.com/moonbit-community/proton.git
cd proton
git checkout 25d77e6236420025ddf1ab04995c0c2a05bba9ed
moon update
proton_cli cef setup
```
