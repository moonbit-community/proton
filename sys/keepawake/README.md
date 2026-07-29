# keepawake

[![coverage](https://img.shields.io/codecov/c/github/justjavac/moonbit-keepawake/main?label=coverage)](https://codecov.io/gh/justjavac/moonbit-keepawake)
[![linux](https://img.shields.io/codecov/c/github/justjavac/moonbit-keepawake/main?flag=linux&label=linux)](https://codecov.io/gh/justjavac/moonbit-keepawake)
[![macos](https://img.shields.io/codecov/c/github/justjavac/moonbit-keepawake/main?flag=macos&label=macos)](https://codecov.io/gh/justjavac/moonbit-keepawake)
[![windows](https://img.shields.io/codecov/c/github/justjavac/moonbit-keepawake/main?flag=windows&label=windows)](https://codecov.io/gh/justjavac/moonbit-keepawake)

`keepawake` is a native-only MoonBit module that exposes a small, readable API
for keeping a machine awake while long-running work is in progress.

This first iteration focuses on a minimal public surface that is easy to
maintain and easy to extend:

- `acquire` returns a guard that starts the native keep-awake request.
- `Guard::release` ends the request and is safe to call more than once.
- `with_keepawake` wraps scoped work and releases automatically.
- `Scope` keeps the policy choice explicit without exposing backend details.

## Install

Add the module to your project, then import `justjavac/keepawake`.

```bash
moon add justjavac/keepawake
```

Package configuration:

```moonbit
import {
  "justjavac/keepawake",
}
```

## API Overview

```moonbit
let guard = @keepawake.acquire(
  reason="Rendering a long animation",
  scope=@keepawake.Scope::PreventSystemAndDisplaySleep,
)

// ... perform the long-running work ...

guard.release()
```

Use the scoped helper when you want automatic cleanup:

```moonbit
let result = @keepawake.with_keepawake(
  () => {
    // ... perform the long-running work ...
    "done"
  },
  reason="Syncing a large local cache",
  scope=@keepawake.Scope::PreventSystemSleep,
)
```

## Platform Notes

### Windows

The Windows backend uses `SetThreadExecutionState`, which is the standard API
for declaring thread-level execution requirements.

### macOS

The macOS backend creates IOKit power assertions. The implementation loads the
required frameworks dynamically so the package does not need platform-specific
linker flags for this minimal version.

### Linux

The Linux backend uses `systemd-inhibit` as the smallest maintainable
cross-distribution starting point for this first version.

- `PreventSystemSleep` maps to `sleep`
- `PreventDisplaySleep` maps to `idle`
- `PreventSystemAndDisplaySleep` maps to `idle:sleep`

In headless or non-systemd environments the module may raise
`BackendUnavailable` with a descriptive message instead of pretending the
request succeeded.

## Examples

Run the example module from the repository root:

```bash
moon -C examples run basic
```

The example acquires a guard, keeps the machine awake for roughly five seconds,
and then releases it.

## License

MIT
