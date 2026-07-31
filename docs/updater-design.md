# Proton Updater Design

Status: draft for review. Nothing in this document is implemented.

An updater is a remote code execution channel that the application installs on
itself deliberately. Every decision here is made from that starting point: the
transport is assumed hostile, the hosting server is assumed to be compromisable,
and the only thing standing between a user and an attacker-supplied binary is a
signature the application can verify offline.

## Scope

Version 1 delivers full-artifact updates for a single-user application install,
driven by the application's own backend.

Non-goals for version 1, each deferred deliberately:

- Differential or layered downloads. See [Artifact size](#artifact-size).
- A resident background update service. Updates are checked while the
  application runs.
- Staged rollout percentages, A/B cohorts, or server-side targeting.
- System-wide or multi-user installs.
- Updating the CEF runtime independently of the application.

## Artifact size

The shipped runtime is large. Measured on `darwin-arm64` at Proton 0.1.13:

| Component | Size | Changes when |
| --- | --- | --- |
| CEF framework | ~390 MB | Proton bumps its CEF version |
| Proton runtime (`libproton`, `cef_process`) | ~460 KB | Every Proton release |
| Application binary and frontend assets | Single-digit MB, typically | Every application release |

A packaged application inherits all three. A real example: the Draw application
packages to a 224 MB ZIP.

A full-artifact update therefore transfers the entire CEF framework even when
only the application layer changed. This is understood and accepted for version
1: correctness of the trust chain is independent of transfer size, and a layered
scheme requires per-layer version tracking that is better designed after there
is operating experience with the simple case.

The manifest schema below reserves the extension point so that layered and
delta artifacts can be introduced without a breaking schema change.

## Threat model

| Adversary | Capability | Mitigation |
| --- | --- | --- |
| Network attacker | Observe and modify traffic | TLS for transport, plus an artifact signature that TLS does not provide |
| Compromised host or CDN | Serve arbitrary bytes at the update URL | ECDSA P-256 signature; the private key never touches the distribution host |
| Rollback attacker | Replay an older, validly signed release to reintroduce a fixed vulnerability | Strict version monotonicity enforced on the client |
| Compromised renderer | Execute arbitrary script in the page | The renderer cannot choose a URL and cannot apply an update; see [Renderer surface](#renderer-surface) |
| Local attacker | Write to the staging directory between download and apply | Signature is re-verified at apply time, not only at download time; staging directory is created private to the current user |
| Manifest substitution | Serve a manifest that points a current version at an attacker-chosen artifact | The manifest is signed; version and artifact digest are covered by that signature |
| Manifest pinning | Serve a stale manifest so the client never learns about a fix | The signed manifest carries `published_at`; a manifest older than the configured freshness window is refused |

TLS authenticates the server, not the payload. A signature is required
independently because the distribution host is explicitly inside the threat
model.

## Manifest

A static JSON document. No update server is required: any object store, GitHub
release asset, or plain HTTP host can serve it.

```json
{
  "schema_version": 1,
  "version": "0.2.0",
  "published_at": "2026-08-01T00:00:00Z",
  "notes_url": "https://example.com/releases/0.2.0",
  "platforms": {
    "darwin-arm64": {
      "kind": "full",
      "url": "https://example.com/MyApp-0.2.0-darwin-arm64.zip",
      "size": 234881024,
      "sha256": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
      "signature": "8Qk3vN2pLzR7aWc...base64 of the 64-byte r||s pair..."
    }
  }
}
```

Rules:

- `schema_version` is rejected when unknown. This follows the discipline already
  applied to `moon.proton` and the native runtime and window configs: unknown
  top-level fields are an error, never silently ignored.
- Platform keys reuse the identifiers Proton already uses everywhere else:
  `darwin-arm64`, `darwin-x64`, `win32-x64`, `linux-x64`. Introducing a second
  naming scheme for the same concept would be a defect.
- `kind` is `"full"` in version 1. It is the extension point: `"layered"` and
  `"delta"` can be added later, and a client that does not understand a `kind`
  treats that platform entry as unavailable rather than failing the whole
  manifest.
- `sha256` is for integrity and resumable download bookkeeping. It is **not** a
  security control; only `signature` is.
- A platform absent from `platforms` means no update is offered for it. This is
  not an error.

## Signature

ECDSA P-256 over SHA-256, applied twice: once over the manifest and once over
each artifact.

### Why P-256, and who verifies

Verification is the one function in this design that gates remote code
execution. The goal is therefore to write none of it. P-256 is the only widely
supported signature algorithm that every target platform can verify with its own
audited implementation:

| Platform | Verification API |
| --- | --- |
| macOS | `SecKeyVerifySignature` (Security.framework) |
| Windows | `BCryptVerifySignature` with `BCRYPT_ECDSA_ALGORITHM`, P-256 curve |
| Linux | `EVP_DigestVerify` (OpenSSL libcrypto) |

Ed25519 was the first choice and was rejected: Windows CNG does not expose it
for signature verification. CNG has supported Curve25519 since Windows 10, but
for ECDH key agreement, not for EdDSA signatures. Choosing Ed25519 would
therefore require shipping a signature implementation — either a third-party
package at version 0.x or a vendored C library — and trusting it with the whole
update channel. Neither the MoonBit core library nor `moonbitlang/x` provides
any asymmetric signature algorithm, so there is no first-party option.

The cost of this choice is three small platform bindings instead of one, and a
libcrypto dependency on Linux. The Linux runtime already links GTK and X11, so
this does not change its dependency posture.

### Wire format

The three APIs disagree about signature encoding: CNG takes a fixed 64-byte
`r || s`, while Security.framework and OpenSSL take a DER-encoded X9.62
`SEQUENCE`. The wire format is therefore **fixed-length raw `r || s`, 64 bytes**,
and the macOS and Linux bindings wrap it into DER before calling.

This direction is deliberate. Wrapping a known-length pair into DER is total and
cannot fail on hostile input; parsing attacker-supplied DER is the opposite, and
lenient ECDSA DER parsers are a recurring source of signature-malleability and
forgery defects. Nothing in this design ever parses untrusted DER.

### Verification input

Signatures are verified over a **digest**, never over a whole artifact.
MoonBit streams the artifact through `@crypto.sha256` and passes the resulting
32 bytes to native code. A 224 MB artifact therefore never crosses the ABI, and
the native surface keeps the small caller-owned buffers the existing ABI rules
require. All three platform APIs accept a pre-computed digest.

### Key format

A trusted key carries its algorithm:

```
p256:MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...
```

An unknown prefix is rejected, not guessed. Tagging the algorithm now means a
future migration — to a post-quantum scheme, or away from P-256 for any other
reason — does not require a release that existing installations cannot accept.
This is the same forward-compatibility argument as the trusted key list, and it
is equally impossible to retrofit.

### What is signed

**Manifest signature.** A detached signature over the exact bytes of the
manifest file, published beside it as `latest.json.sig`. Detached and
byte-exact, rather than a signature field embedded in the JSON, because an
embedded signature requires a canonicalisation rule — which fields are excluded,
how keys are ordered, how numbers are formatted — and every disagreement between
signer and verifier about that rule is a forgery opportunity. Signing the file
as transmitted has no such rule.

Because the manifest carries `version` and each artifact's `sha256`, this
signature binds a version to a specific artifact. That is what defeats manifest
substitution, and together with `published_at` it is what makes staleness
detectable.

**Artifact signature.** A detached signature over the raw artifact bytes. This
is partly redundant with the manifest signature plus digest, and is kept anyway
for two reasons: the artifact stays self-authenticating if it is ever obtained
through another path, and apply-time re-verification does not have to retain and
re-parse the manifest.

Both signatures must verify. Either failing aborts the update.

Key handling:

- Key pairs are generated by `proton_cli updater keygen`. A private key never
  enters the repository and never enters the distribution host. One key pair
  signs both the manifest and the artifacts of a given release.
- ECDSA signing consumes a per-signature random nonce, and a reused or biased
  nonce discloses the private key. Signing therefore uses a platform or
  libcrypto implementation, never a hand-rolled one. This is a signer-side
  risk confined to a maintainer machine or CI, unlike a verification defect,
  which an attacker can trigger at will.
- Trusted public keys are declared in `moon.proton` as a **list**. A signature
  verifies if it matches any key in that list. See [Key rotation](#key-rotation)
  for why this is a list from the first release rather than a single value.
- Public keys are never read from the manifest, because a key supplied by the
  thing being authenticated authenticates nothing.
- Signature verification cannot be disabled by configuration. There is no
  `insecure` escape hatch: one exists in every updater that has later been
  exploited through it.

### Key rotation

The mechanism comparable frameworks use is *chained rotation*: publish a release
signed with the old key whose configuration trusts the new key, so existing
installations accept it and thereafter trust the new key. Sparkle and Tauri both
work this way.

Chained rotation has two failure modes, and the second is the reason this
section exists:

- An installation that skips the transition release — offline for a long period,
  or the transition release was withdrawn — is stranded on the old key while
  releases are signed with the new one.
- **A lost or leaked key cannot be recovered in band at all.** Producing the
  transition release requires signing with the key you no longer control. Every
  existing installation is stranded and must reinstall out of band. Tauri has
  had a real instance of updater private keys leaking through build-time
  environment variables, so this is not a hypothetical.

Trusting a list instead of a single key removes both:

```moonbit
updater = {
  public_keys: [
    "p256:MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...",  // active signer
    "p256:MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAF...",  // reserve, held offline
  ],
}
```

A reserve key is distributed in the trusted list long before it is used. When
rotation is needed, signing simply switches to the reserve key: no transition
release is required, so installations that skipped releases still update, and a
compromised active key can be abandoned immediately rather than after a release
that can no longer be produced.

This has to be decided before the first key is published. Narrowing a list to a
single value later is harmless; widening a single value to a list requires a
transition release, which is exactly the mechanism being replaced.

macOS carries a second, independent trust anchor: the application is code-signed
by Apple, and Sparkle's rule is that either anchor may be rotated while the other
holds. So even a total loss of updater keys is recoverable on macOS while the
Developer ID certificate is intact. The portable Windows and Linux layouts have
only one anchor and no such recovery, which is one more consequence of having no
installer on those platforms.

A threshold scheme, where signing requires *m* of *n* keys and no single loss is
fatal, is the mature form of this. The Update Framework specifies it, and PyPI,
Docker Notary, and Uptane implement it. It is out of scope for version 1; a
trusted list is the part of it that costs nothing to adopt now.

Putting the public key in configuration rather than in application source makes
rotation easy, and it inherits whatever integrity protection the packaged layout
provides. On macOS the config ships inside a code-signed bundle, so altering it
breaks that signature. **The Windows portable ZIP and the current Linux layout
have no equivalent protection**, so on those platforms an attacker with local
write access can replace the trusted key. This is one more consequence of having
no real installer on those platforms, and it should be revisited when they gain
one.

## Client flow

Implemented in MoonBit, in a new `proton/updater/` package. `moonbitlang/async`
provides `http` (`get`, `get_stream`), `tls`, and `gzip`; `moonbitlang/x/crypto`
provides `sha256`. Signature verification is the one step that calls into native
code, because the verification is performed by the platform rather than by
Proton.

1. **Check.** Fetch the manifest and its detached signature. Verify the
   signature before parsing anything. Reject unknown `schema_version`. Reject a
   manifest whose `published_at` is older than the configured freshness window.
   Select the entry for the running platform.
2. **Compare.** Offer the update only when the manifest version is strictly
   greater than the running version. Equal or lower is not an update; it is a
   rollback attempt or a stale manifest, and both are ignored.
3. **Download.** Stream to
   `app_data_dir()/<identifier>/updates/<version>/artifact`. The staging
   directory is created private to the current user, following the ownership and
   permission checks already used by the single-instance coordinator in
   `native/src/proton_app_instance.c` (`lstat` before trusting a directory,
   `O_NOFOLLOW` on open, refuse group and other permissions).
4. **Verify.** Check `size`, then `sha256`, then the P-256 signature over that digest. A
   failure at any step deletes the staged artifact. A partially verified
   artifact is never retained for a later attempt.
5. **Stage.** Expand the artifact next to the staged download and re-verify the
   platform's own code signature where the platform has one. Mark ready only
   after this completes.
6. **Apply.** Hand the staged path to native code, which performs the swap and
   relaunch. The signature is verified again immediately before the swap,
   closing the window between download and apply.

## Native surface

Two functions, following the existing ABI rules: `proton_*` prefix, status
codes, caller-owned error buffers, no platform types across the boundary.

```c
int32_t proton_verify_p256_sha256(const uint8_t *digest, size_t digest_len,
                                  const uint8_t *signature,
                                  size_t signature_len,
                                  const uint8_t *public_key,
                                  size_t public_key_len, char *error,
                                  size_t error_len);

int32_t proton_update_stage(const char *staged_path, char *error,
                            size_t error_len);
int32_t proton_update_apply_and_relaunch(char *error, size_t error_len);
```

`proton_verify_p256_sha256` takes a 32-byte digest and a 64-byte raw `r || s`
signature and returns a status code. It has no updater-specific knowledge and no
state; it is a thin call into the platform verification API. Keeping it that
narrow is what makes it reviewable.

Everything platform-specific lives behind these three. Given that the three
per-platform engine sources are already near-duplicates of one another — a
duplication that has already produced one identical defect in all three copies —
the shared portion belongs in `native/src/engine/cef_common/` from the start
rather than being written three times. For verification only the API call itself
differs; digest and signature handling are common.

### Per-platform apply

**macOS.** Verify the staged bundle with the platform code-signing check and
confirm its signing identity matches the running application, as Sparkle does;
an update signed by a different identity is refused. Swap the bundle with
`rename` on the same volume, then relaunch. Two conditions must be reported
clearly rather than worked around: an application installed somewhere the user
cannot write, and an application still running from a quarantined or
translocated location.

**Windows.** The correct mechanism is to re-run the installer, which is what
Tauri does. Proton has no Windows installer today; it ships a portable ZIP. A
portable-ZIP path is possible — Windows permits renaming a running executable,
so a helper can rename the old directory, move the new one in, and relaunch —
but it is fragile and leaves no OS-level record of the install. This path is
specified but should not be built before the installer exists.

**Linux.** There is no packaging target at all today. AppImage is the natural
landing point because it has a self-update convention. Blocked on packaging.

**Consequence:** version 1 is macOS-only in practice. This is a packaging
limitation, not an updater limitation, and it is the reason installer work
should precede updater work.

## Configuration

```moonbit
updater = {
  active: true,
  endpoint: "https://example.com/updates/latest.json",
  public_keys: [
    "p256:MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...",
    "p256:MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAF...",
  ],
  check_on_launch: true,
  freshness_days: 30,
}
```

`public_keys` must contain at least one key when `active` is true. An empty list
is a configuration error, not an invitation to skip verification.

`active: false` compiles the updater out of the decision path entirely; an
application that distributes through an app store or a system package manager
must not also update itself.

## Automatic check

The runtime checks on launch by default. Four properties are required of that
default, because a check that runs without the user asking for it is held to a
higher standard than one they triggered.

- **It never blocks startup.** The check runs after the application window is
  up, on the lifecycle task group, not on the startup path.
- **It fails silently.** An unreachable, expired, or malformed manifest produces
  a log line and nothing else. A broken update server must never be able to
  prevent an application from launching, which is exactly what happens when the
  check is treated as a startup precondition.
- **It is spread out.** A fixed delay after launch plus jitter, so that a
  population of installations does not arrive at the endpoint simultaneously
  after a popular release.
- **It is disclosed and can be turned off.** `check_on_launch: false` disables
  it. Contacting a server on every launch is a privacy decision as much as a
  technical one, and applications that cannot make that request on their users'
  behalf need a way to say so.

Finding an update does **not** start a download and does not apply anything. The
runtime reports availability; the application decides what to do with it. The
distinction matters: automatic *checking* is a reasonable default, whereas
automatic *installing* changes the code a user is running without their consent
and is not something a framework should decide for every application.

## Renderer surface

Update capability is exposed through the existing permission model. Registration
alone grants nothing; a window needs an explicit grant for a trusted source and
the `app` extension.

- `app:updater.check` — grantable. Returns availability, version, and notes URL.
- `app:updater.download` — grantable. Reports progress through
  `window.__MoonBit__.app.on("updater.progress", ...)`.
- Applying an update is **not** a renderer capability. A page may request it; the
  backend handler decides. The renderer never supplies a URL, a version, or a
  path.

A renderer that could choose the update URL would hold a remote code execution
primitive over the host. That is the single most important boundary in this
design.

## Release integration

`proton_cli package` gains the ability to emit update metadata alongside the
artifacts it already produces:

- the artifact (existing `app`, `zip`, `dmg` outputs),
- a detached `.sig`,
- a `latest.json` manifest fragment for the built platform.

Signing runs where the private key lives — a maintainer machine or CI with the
key held as a secret — never as part of an ordinary build. Merging per-platform
fragments into one manifest is a separate step because the three platforms are
built on three machines, which is already true of `proton/prebuilt/`.

## Failure handling

- Any verification failure aborts and deletes staged state. The running
  application is never modified.
- The swap is the only irreversible step. It must be ordered so that a crash
  before it leaves the old application intact, and a crash after it leaves the
  new application intact. Nothing may observe a half-swapped bundle.
- Keep the previous bundle until the new one has started successfully once, so a
  failed launch can be recovered. Automatic rollback on repeated launch failure
  is out of scope for version 1; retaining the artifact makes manual recovery
  possible.

## Known limitations

- **Denial of service on the endpoint.** A signed, freshness-bearing manifest
  makes a *stale* manifest detectable, but an attacker who simply blocks the
  endpoint still prevents a client from learning that a fix exists. Nothing in a
  pull-based updater can fix that; the client can only surface prolonged
  unreachability to the application.
- **Trusted key integrity on Windows and Linux.** The trusted key list lives in
  `moon.proton`, which is protected by the code-signed bundle on macOS and by
  nothing on the current portable Windows and Linux layouts. Those platforms
  also lack the second trust anchor that makes key loss recoverable on macOS.
- **Full-artifact transfer.** Documented above and accepted for version 1.
- **macOS only.** Blocked on Windows and Linux packaging targets.

## Phasing

1. Manifest schema, key generation, signing, and `proton_cli` emission. This is
   independently testable and is the input to everything else.
2. MoonBit check, download, and verification, with no apply step. The update can
   be observed and validated end to end without ever modifying an installation.
3. macOS apply and relaunch.
4. Windows and Linux, after their installers exist.

## Open questions

- **Reserve key custody.** A trusted list is only useful if the reserve key is
  stored somewhere the compromise of the active key does not reach. Deciding
  where that is — and who can reach it — is an operational question that the
  design cannot answer.
- **Freshness window default.** Thirty days is a placeholder. Too short and a
  quiet project locks its own users out of updating; too long and a pinning
  attacker gets a wide window.
- **Sequencing against a Proton runtime bump.** An application update that also
  changes the CEF version transfers the whole framework. Version 1 accepts that,
  but it is the point where the layered scheme stops being an optimisation and
  starts being necessary.
