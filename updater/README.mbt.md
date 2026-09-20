# moonbit-community/proton_updater

The update manifest schema, shared by the Proton runtime and `proton_cli`.

## Scope

Decoding and ordering. This module has no network access, no filesystem access,
and no cryptography. Parsing does not verify signatures.

The caller is responsible, in order, for: verifying the manifest signature,
rejecting a `revision` that is not strictly newer than the installed one, and
rejecting a manifest older than its freshness window.

## Decoding

```moonbit nocheck
let manifest = @updater.Manifest::parse(text)
match manifest.platform("darwin-arm64") {
  Some(update) => download(update.url(), update.size())
  None => () // Nothing on offer for this platform.
}
```

`schema_version` must be exactly `2`, `kind` must be `"full"`, and unknown
fields are errors. A release manifest is one strict protocol document: invalid
or unsupported content fails loudly instead of being treated as no update.

## Ordering

`revision` is a positive unsigned 64-bit release sequence. It is the security
ordering: every published update increments it, and it never resets when the
display version changes. Keeping it separate lets applications use ordinary
version labels without making rollback prevention depend on semantic-version
policy.

`Version` is exactly three non-negative integers, with no leading zeros and no
pre-release or build suffix. It is display metadata, not the install ordering;
the strict shape keeps manifests predictable while `revision` decides whether
an artifact may replace the installed application.

`Timestamp` accepts only `YYYY-MM-DDTHH:MM:SSZ`; numeric offsets are refused.

## Encodings

`sha256` and `signature` must be lowercase hexadecimal.

Artifact URLs must use `https`.
