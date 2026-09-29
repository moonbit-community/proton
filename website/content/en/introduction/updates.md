# Application updates

Application updates replace the distributed application, not the development CLI or Mooncakes dependencies. Configure `App.update_channel(endpoint, public_keys, check_on_launch?, freshness_days?)` before running the app.

## Channel and checks

The endpoint must use HTTPS and there must be at least one trusted RSA public key. Automatic checking defaults to enabled; manifest freshness defaults to 30 days and must be positive. Keys use the format validated by [`updater public-key`](../command-line-interface/index.md#updater-public-key).

The automatic check runs after successful startup and reports failures through logging without making startup fail. For explicit checks, use `ApplicationContext.check_for_update()` and handle its result and errors. `NotConfigured` is distinct from `UpToDate`; a context used after its application ends no longer has an active channel.

An offered `PendingUpdate` has passed manifest trust, freshness and revision checks. It exposes version, revision, size and optional notes URL, but the artifact has not yet been downloaded.

## Install and restart

Installation is explicit: `PendingUpdate.install()` downloads into a private stage and verifies size, digest and signature before the stage can be consumed. Inspect `UpdateInstallOutcome` rather than assuming every platform has already replaced its files. macOS and Linux apply the replacement during install; Windows retains a verified NSIS installer for restart.

`PendingUpdate.restart()` requests launching the replacement; the caller should then exit. A successful request means the OS accepted the launch, not that the new process reached readiness. Checking or receiving an update notification never implicitly installs an update.

Keep the application's unsaved-work decisions separate from checking and downloading. Use the [quit lifecycle](lifecycle.md) for exit decisions. Old managed update artifacts are cleaned after successful startup, so a newly staged package is not evidence that startup succeeded.

## Publisher responsibilities

Package a stable application identifier with a monotonically increasing revision. The updater metadata options in [CLI package](../command-line-interface/index.md#package) describe the artifact location, publication instant and revision. `updater public-key` only formats a public key; it does not generate keys, sign an update manifest or host an endpoint. OS signing/notarization and updater signature verification serve different checks; configuring one does not configure the other.
