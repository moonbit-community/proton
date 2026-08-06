# moonbit-community/proton_cdp

![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)
![Non-generated library coverage](https://img.shields.io/badge/non--generated%20library%20coverage-100%25-brightgreen.svg)

MoonBit library for the Chrome DevTools Protocol (CDP).

## Features

- Target parsing: `9222`, `host:port`, HTTP discovery URLs, browser/page
  WebSocket URLs.
- Discovery: `/json/version`, `/json/list`, `/json/protocol`.
- Commands: raw, bundled-schema-validated, remote-schema-checked, generated
  typed builders.
- Events: buffering, filtering, synchronous handlers.
- Targets: browser-level `Target.*` helpers and flattened sessions.
- Launch: optional Chrome/Edge/Chromium startup with remote debugging.

## Packages

| Package | Purpose |
| --- | --- |
| `moonbit-community/proton_cdp/protocol` | Wire types, bundled manifest, schema validation, remote schema diff. |
| `moonbit-community/proton_cdp/protocol/typed` | Generated params, command builders, event builders, result decoders. |
| `moonbit-community/proton_cdp/client` | Discovery, WebSocket client, event buffer, target helpers, launch helpers. |

## Docs

Start at [docs/README.mbt.md](docs/README.mbt.md).

## Quick Start

Install deps:

```bash
moon install
```

Start Chrome with remote debugging:

```bash
chrome --remote-debugging-port=9222 --user-data-dir=/tmp/mbt-cdp-profile
```

PowerShell:

```powershell
& "C:\Program Files\Google\Chrome\Application\chrome.exe" `
  --remote-debugging-port=9222 `
  --user-data-dir="$env:TEMP\mbt-cdp-profile"
```

Browser-level command:

```mbt nocheck
let target = @client.parse_cdp_target("9222")
let browser = @client.connect_cdp_browser_target(target)
defer browser.close()

let response = browser.send_schema_command("Browser.getVersion")
println(@client.cdp_response_result_json(response).stringify())
```

Page-level command:

```mbt nocheck
let page = @client.connect_cdp_page_target(@client.parse_cdp_target("9222"))
defer page.close()

let response = page.send_schema_command(
  "Runtime.evaluate",
  params={
    "expression": "1 + 1",
    "returnByValue": true,
  },
)
println(@client.cdp_response_result_json(response).stringify())
```

Typed command builders live in `moonbit-community/proton_cdp/protocol/typed`, for example
`@typed.runtime_evaluate_command`.

## Command Modes

- Raw: `send_cdp_command` + `recv_cdp_response`.
- Schema-aware: `send_schema_command`.
- Remote-schema-aware: `send_remote_schema_command`.
- Typed: generated builders + `send_cdp_message`.

## Examples

```powershell
$env:MBT_CDP_TARGET = "9222"
$env:MBT_CDP_EXAMPLE = "discover_version"
moon -C examples run cmd

$env:MBT_CDP_EXAMPLE = "runtime_evaluate"
moon -C examples run cmd
```

## Checks

```bash
moon test
node tools/check_non_generated_coverage.mjs 100
```

Opt-in real-browser E2E:

```powershell
$env:MBT_CDP_E2E = "1"
$env:MBT_CDP_TARGET = "9222"
moon test client --filter "*real Chrome CDP E2E*"
```

## License

Apache-2.0. See [LICENSE](LICENSE).
