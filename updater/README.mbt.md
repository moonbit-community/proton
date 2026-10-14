# moonbit-community/proton_updater

The update manifest schema, shared by the Proton runtime and `proton_cli`.

## Scope

Decoding and ordering. This module has no network access, no filesystem access,
and no cryptography. Parsing does not verify signatures.

The caller is responsible, in order, for: verifying the manifest signature,
rejecting a `version` that is not strictly newer than the installed one, and
rejecting a manifest older than its freshness window.

## Decoding

```moonbit nocheck
let manifest = @updater.Manifest::parse(text)
match manifest.platform("darwin-arm64") {
  Some(update) => download(update.url(), update.size())
  None => () // Nothing on offer for this platform.
}
```

`schema_version` must be exactly `3`, `kind` must be `"full"`, and unknown
fields are errors. A release manifest is one strict protocol document: invalid
or unsupported content fails loudly instead of being treated as no update.

## Ordering

`version` is the application's `package.version` and the only release ordering.
The updater offers only strictly newer versions and rechecks ordering under the
native install lock. Rebuilding the same version does not create an update.

`Version` is exactly three non-negative Int32 components, with no leading zeros
and no pre-release or build suffix. Components compare numerically, so `0.10.0`
is newer than `0.9.0`.

Schema 3 removes schema 2's separate release counter. The schemas are not
interchangeable. Keep schema 2 endpoints available to existing clients. Those installations
require a manual upgrade or a deliberately prepared transition release before
using a separate schema 3 endpoint.

`Timestamp` accepts only `YYYY-MM-DDTHH:MM:SSZ`; numeric offsets are refused.

## Encodings

`sha256` and `signature` must be lowercase hexadecimal.

Artifact URLs must use `https`.
