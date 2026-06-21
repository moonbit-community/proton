# proton/catalog

`justjavac/proton/catalog` discovers extension metadata without importing
extension code.

It scans explicit search roots for `moon.ext`, loads descriptors, and builds
deterministic link plans from declared extension dependencies.

Catalog metadata is for tooling. Applications still link extensions explicitly
in MoonBit code.
