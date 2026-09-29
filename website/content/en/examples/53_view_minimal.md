# Embedded browser view

A declarative child browser alongside a host sidebar.

[53_view_minimal](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/53_view_minimal) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/53_view_minimal/main.mbt)

## Behavior

with_view() adds a browser at x=288 with an 832 × 720 viewport. It loads example.com separately from the host HTML.

## Run

[Environment requirements](../introduction/installation.md) apply. From the checked-out repository root:

```sh
moon -C examples run 53_view_minimal --target native
```

## Limits and interpretation

The remote page requires network access. Bounds are fixed in this minimal example; responsive view layout belongs to the application. Parent shutdown ends the child lifetime.
