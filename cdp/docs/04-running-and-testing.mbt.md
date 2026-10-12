# Running and testing

This page covers local browser launch and library tests.

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

The launcher does not own the browser's lifetime. Close it through the CDP
`Browser.close` command or manage the child process yourself. Always use a
separate profile directory for automation.

## Run tests

From the Proton repository root:

```sh
moon -C cdp test --target native
node cdp/tools/gen_protocol_manifest.mjs --check
```

The release workflow also builds a consumer outside the workspace with registry
dependencies and checks page evaluation against headless Chrome.

## Test against Proton

The repository's self-hosted E2E suite uses this library to automate Proton:

```sh
moon -C e2e run test --target native -- --self-hosted
```

This requires the Proton native build prerequisites and CEF setup described in
the repository's maintainer guide. External applications can build their own
checks using the [minimal consumer](../README.mbt.md#connect-to-a-proton-application).
