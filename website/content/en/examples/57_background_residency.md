# Background residency

A single-instance app survives closing its last window.

[57_background_residency](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/57_background_residency) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/57_background_residency/main.mbt)

## Behavior

KeepRunning retains the process. A second launch delivers Reopen; the handler recreates main only when it is absent.

## Run

[Environment requirements](../introduction/installation.md) apply. From the checked-out repository root:

```sh
moon -C examples run 57_background_residency --target native
```

## Limits and interpretation

Closing the window intentionally does not quit. End the process using the platform Quit action or stop the development command. This differs from the default last-window policy.
