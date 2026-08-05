# justjavac/cdp documentation

`justjavac/cdp` is a MoonBit library for the Chrome DevTools Protocol
(CDP). It provides direct access to CDP messages with protocol metadata,
schema-aware validation, generated typed command builders, remote debugging
discovery, a WebSocket CDP client, target helpers, event buffering, and
optional local Chrome launch support.

## Packages

- `justjavac/cdp/protocol`
  - CDP command, response, event, and error wire structs.
  - Bundled protocol manifest lookup.
  - Schema-aware command, event, and response validation.
  - Remote `/json/protocol` summary and diff helpers.
- `justjavac/cdp/protocol/typed`
  - Generated typed parameter structs.
  - Generated command builders for the bundled protocol.
  - Generated event builders and result decoders.
- `justjavac/cdp/client`
  - Remote debugging discovery over `/json/version`, `/json/list`, and
    `/json/protocol`.
  - WebSocket CDP client.
  - Raw, bundled-schema, and remote-schema-aware send helpers.
  - Event buffering and handler registration.
  - Browser target helpers and optional Chrome launch helpers.

## Guide

- [Getting started](01-getting-started.mbt.md): requirements, imports, target parsing,
  discovery, and connecting to browser or page targets.
- [Commands and schemas](02-commands-and-schemas.mbt.md): raw commands, schema-aware
  commands, typed commands, and remote protocol comparison.
- [Events and targets](03-events-and-targets.mbt.md): event buffering, handlers, and
  flattened target sessions.
- [Running and testing](04-running-and-testing.mbt.md): launching Chrome, examples,
  unit tests, coverage, and real-browser E2E tests.
- [Troubleshooting](05-troubleshooting.mbt.md): common connection and protocol issues.

## License

Apache-2.0. See `LICENSE`.
