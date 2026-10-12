# moonbit-community/proton_cdp

An optional native MoonBit library for automating Proton and other Chromium-based
applications through CDP.

See [installation, usage, and compatibility](README.mbt.md) and the
[full guide](docs/README.mbt.md).

## Maintainer checks

```sh
moon -C cdp test --target native
node cdp/tools/gen_protocol_manifest.mjs --check
```

Generated protocol bindings are committed; consumers do not run the generator.

Apache-2.0. See [LICENSE](LICENSE).
