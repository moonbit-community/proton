# moonbit-community/proton_updater

The update manifest schema, shared by the Proton runtime and `proton_cli`.

The runtime reads manifests; the CLI writes them. Putting the schema in its own
module keeps one definition of the format rather than two that drift, and lets
the CLI depend on it without depending on the whole runtime.

## Scope

Decoding and ordering. This module has no network access, no filesystem access,
and no cryptography — it does not verify signatures, only carries them. That
separation is deliberate: decoding a manifest proves it is well formed and
nothing more, and a type that could be mistaken for a trusted manifest is worse
than one that obviously is not.

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

`schema_version` must be exactly `2`, and unknown fields are an error rather
than something to skip — the same discipline Proton's structured native
runtime configs follow, so that a typo in a release manifest fails
loudly instead of silently omitting whatever it was meant to say.

One case deliberately does **not** fail: a platform entry whose `kind` this
client does not implement is treated as no update on offer. Failing the whole
document would let a newer release format lock every older client out of every
platform at once, including the platforms it could still have served.

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

`Timestamp` accepts only `YYYY-MM-DDTHH:MM:SSZ`. Every field is fixed width in
that form, so lexicographic order is chronological order and `is_before` needs
no calendar arithmetic. Numeric offsets are refused because comparing them would
require converting them, and a freshness check that silently mis-converts is a
check that has quietly stopped working.

## Encodings

`sha256` and `signature` are hexadecimal, lowercase, and strictly validated:
one encoding across the manifest and the key format means one strict decoder
rather than two that can disagree.

Artifact URLs must be `https`. The signature is checked regardless, so this is
not what makes an update safe; it removes an opportunity rather than a defence.
