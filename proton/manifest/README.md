# proton/manifest

`justjavac/proton/manifest` defines the runtime manifest types shared by
bootstrap, native handoff, and the root facade.

It is a data package. Parsing belongs in `bootstrap`; application lifecycle
belongs in the root `proton` facade.
