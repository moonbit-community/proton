# Embedded browser view

[中文](../zh/examples/53_view_minimal.html)

A declarative child browser alongside a host sidebar.

[53_view_minimal](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/53_view_minimal) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/53_view_minimal/main.mbt)

## Behavior

with_view() adds a browser at x=288 with an 832 × 720 viewport. It loads example.com separately from the host HTML.

## Run

[Environment requirements](../installation.md) apply. From the checked-out repository root:

```sh
moon -C examples run 53_view_minimal --target native
```

## Limits and interpretation

The remote page requires network access. Bounds are fixed in this minimal example; responsive view layout belongs to the application. Parent shutdown ends the child lifetime.
