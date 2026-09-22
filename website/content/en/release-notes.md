# Release Notes

[中文](zh/release-notes.html)

## 0.3.3 — 2026-09-21

- **View lifecycle:** removed and explicitly closed child views retain the identity needed to deliver their terminal close event. Coverage includes views closed before browser creation and stale events after replacement. [PR #378](https://github.com/moonbit-community/proton/pull/378)
- **Dependencies:** async 0.22.1, x 0.5.5, lexer/parser/moon_config 0.4.0, Rabbita 0.16.2 and Warren 0.3.3. Scaffold defaults and documentation now use these versions. Cancellation handling and protected cleanup follow async's new semantics. [PR #379](https://github.com/moonbit-community/proton/pull/379)
- **Release:** all workspace modules advance together to 0.3.3; the CEF engine version is unchanged. [Release PR](https://github.com/moonbit-community/proton/pull/380) · [Successful publication](https://github.com/moonbit-community/proton/actions/runs/35577888216)

### Updating an application

Use 0.3.3 consistently for the application's `proton_*` dependencies and CLI. Existing projects retain their configuration and source; installing a new CLI does not rewrite them. Install Warren 0.3.3 when using the isomorphic frontend, and run `proton_cli cef setup` for the matching helper before building.

Applications that directly use async should review its 0.22 cancellation behavior: cancellation is no longer caught as an ordinary error. A cancelled task's `wait()` can report `TaskCancelled`; child process shutdown can complete with an exit result after reaping.

### Earlier release history

[0.3.2 release preparation](https://github.com/moonbit-community/proton/pull/377) and [repository history](https://github.com/moonbit-community/proton/commits/main/) contain earlier changes. This page starts detailed release notes at 0.3.3.
