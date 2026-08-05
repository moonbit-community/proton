# Running and testing

This page covers local browser launch, repository examples, normal tests,
coverage, and opt-in real-browser E2E tests.

## Launch Chrome from MoonBit

`launch_browser` can start a Chrome-family browser with remote debugging
enabled:

```mbt nocheck
let options = {
  ..@client.default_launch_options(),
  browser_path: Some("C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"),
  headless: true,
  port: 0,
  user_data_dir: "_build/mbt-cdp-profile",
}

let launched = @client.launch_browser(options)
println(launched.web_socket_url)
```

Use `port: 0` to let Chrome choose a free port. The launcher waits for
Chrome's `DevToolsActivePort` file and returns the actual endpoint.

## Run the examples

The repository includes one standalone examples package. Select the example
with `MBT_CDP_EXAMPLE`:

- `discover_version`
- `runtime_evaluate`

PowerShell:

```powershell
$env:MBT_CDP_TARGET = "9222"
$env:MBT_CDP_EXAMPLE = "discover_version"
moon -C examples run cmd
$env:MBT_CDP_EXAMPLE = "runtime_evaluate"
moon -C examples run cmd
```

POSIX shell:

```bash
MBT_CDP_TARGET=9222 MBT_CDP_EXAMPLE=discover_version moon -C examples run cmd
MBT_CDP_TARGET=9222 MBT_CDP_EXAMPLE=runtime_evaluate moon -C examples run cmd
```

`runtime_evaluate` needs at least one page target in the remote debugging
instance.

## Run tests

Unit and compile-time tests do not require a browser:

```bash
moon test
```

The maintained library code is gated at 100% non-generated coverage:

```bash
node tools/check_non_generated_coverage.mjs 100
```

Generated typed CDP files and executable examples are excluded from this gate.
Generated files are checked by generator tests and compile-time coverage
counters; examples require a live browser endpoint.

## Run real-browser E2E tests

Real-browser E2E tests are opt-in:

```powershell
$env:MBT_CDP_E2E = "1"
$env:MBT_CDP_TARGET = "9222"
moon test client --filter "*real Chrome CDP E2E*"
```

Useful environment variables:

- `MBT_CDP_TARGET`: existing remote debugging endpoint.
- `MBT_CDP_BROWSER`: Chrome, Edge, or Chromium executable path.
- `MBT_CDP_E2E_HEADLESS=0`: run launched browser headed.
- `MBT_CDP_E2E_PROFILE`: profile directory for launch-based E2E.

The E2E flow checks discovery, target creation, target attach, Page/Runtime/DOM
and Network commands, event buffering, and cleanup.
