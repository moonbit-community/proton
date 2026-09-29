# Release Notes

## 0.3.4 — 2026-09-28

This book targets the published [0.3.4 source](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa). The [publication and registry acceptance workflow](https://github.com/moonbit-community/proton/actions/runs/36407926563) completed successfully. Warren remains a separate dependency at 0.3.3.

- **Lifecycle:** application quit interception and forced exit, application-level window/browser/session events, and focus/visibility controls. Fixes cover forced exit during `will_quit`, `exit(0)`, child-renderer termination, page recovery, and closed-window collection.
- **Communication:** preserve command error codes, separate command failures from runtime failures, and remove the global pending-request limit. Extension operation inventories now come from bindings.
- **Browser APIs:** navigation history and inserted CSS controls; task metrics distinguish CEF tasks from processes.
- **Platforms and packaging:** Windows desktop media consent and child-view geometry fixes; macOS query autorelease pools and alert layout; recoverable packaging locks, explicit minimum macOS version metadata, and executable Linux helpers in AppImage staging.
- **CLI:** explicit `new` options no longer prompt again. Async is updated to 0.22.4.

### Upgrade notes

Keep the CLI and application `proton_*` modules on 0.3.4 and run `proton_cli cef setup` for the matching helper. Reinstalling the CLI does not rewrite existing projects.

The briefly introduced `app_metrics` API is now `task_metrics` with `AppTaskMetric`: task identity is not process identity, and `hosting_process_usage` can repeat across tasks. Do not sum task rows as application resource usage. See [PR #412](https://github.com/moonbit-community/proton/pull/412). Unused legacy command configuration APIs were removed in [PR #408](https://github.com/moonbit-community/proton/pull/408); application command bindings remain the supported route.

## 0.3.3 — 2026-09-21

- **View lifecycle:** removed and explicitly closed child views retain the identity needed to deliver their terminal close event. Coverage includes views closed before browser creation and stale events after replacement. [PR #378](https://github.com/moonbit-community/proton/pull/378)
- **Dependencies:** async 0.22.1, x 0.5.5, lexer/parser/moon_config 0.4.0, Rabbita 0.16.2 and Warren 0.3.3. Scaffold defaults and documentation now use these versions. Cancellation handling and protected cleanup follow async's new semantics. [PR #379](https://github.com/moonbit-community/proton/pull/379)
- **Release:** all workspace modules advance together to 0.3.3; the CEF engine version is unchanged. [Release PR](https://github.com/moonbit-community/proton/pull/380) · [Successful publication](https://github.com/moonbit-community/proton/actions/runs/35577888216)

### Updating an application

Use 0.3.3 consistently for the application's `proton_*` dependencies and CLI. Existing projects retain their configuration and source; installing a new CLI does not rewrite them. Install Warren 0.3.3 when using the isomorphic frontend, and run `proton_cli cef setup` for the matching helper before building.

Applications that directly use async should review its 0.22 cancellation behavior: cancellation is no longer caught as an ordinary error. A cancelled task's `wait()` can report `TaskCancelled`; child process shutdown can complete with an exit result after reaping.

### Earlier release history

[0.3.2 release preparation](https://github.com/moonbit-community/proton/pull/377) and [repository history](https://github.com/moonbit-community/proton/commits/main/) contain earlier changes. This page starts detailed release notes at 0.3.3.
