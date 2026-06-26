# Proton E2E

CDP-based end-to-end smoke probes for the native DLL bridge route.

The module is intentionally separate from the root workspace. Before running it
from this repository, add it to the current MoonBit workspace:

```sh
moon work use ./e2e
```

Then start an example with remote debugging enabled and run:

```sh
MBT_PROTON_E2E_SCENARIO=41_app_commands MBT_CDP_TARGET=9222 moon -C e2e run test --target native
```

The current v1 probe covers `window.__MoonBit__.core.invokeOp(...)` for
`41_app_commands`.
