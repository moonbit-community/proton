# Background residency

[中文](../zh/examples/57_background_residency.html)

A single-instance app survives closing its last window.

[57_background_residency](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/57_background_residency) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/57_background_residency/main.mbt)

## Behavior

KeepRunning retains the process. A second launch delivers Reopen; the handler recreates main only when it is absent.

## Run

[Environment requirements](../installation.md) apply. From the checked-out repository root:

```sh
moon -C examples run 57_background_residency --target native
```

## Limits and interpretation

Closing the window intentionally does not quit. End the process using the platform Quit action or stop the development command. This differs from the default last-window policy.
