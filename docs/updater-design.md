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
| Compromised host or CDN | Serve arbitrary bytes at the update URL | RSA signature; the private key never touches the distribution host |
| Rollback attacker | Replay an older, validly signed release to reintroduce a fixed vulnerability | Strict version monotonicity enforced on the client |
| Compromised renderer | Execute arbitrary script in the page | The renderer cannot choose a URL and cannot apply an update; see [Renderer surface](#renderer-surface) |
| Local attacker | Replace a staged path between validation and installation | The authenticated archive bytes cross into one native install transaction. Native code creates a 0700 directory with `mkdtemp`, expands there, validates the bundle signature and identity, and replaces the application without exposing the expanded path between those operations |
| Manifest substitution | Serve a manifest that points a current version at an attacker-chosen artifact | The manifest is signed; version and artifact digest are covered by that signature |
| Manifest pinning | Serve a stale manifest so the client never learns about a fix | The signed manifest carries `published_at`; a manifest older than the configured freshness window is refused. The window is measured against the system clock, so this defence is only as good as that clock — a client whose clock is wrong refuses every update rather than accepting a stale one, which is the safe direction but not a silent one |

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
      "signature": "3e23cf2dff913700...hex of the 256-byte signature..."
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
- `sha256` and `signature` are hexadecimal, matching the key format. One
  encoding throughout means one strict decoder rather than two.
- `sha256` is for integrity and resumable download bookkeeping. It is **not** a
  security control; only `signature` is.
- A platform absent from `platforms` means no update is offered for it. This is
  not an error.

## Signature

RSASSA-PKCS1-v1_5 over SHA-256, applied twice: once over the manifest and once
over each artifact. Verification is implemented in `justjavac/proton_rsa`.

### Why RSA, and who verifies

Verification is the one function in this design that gates remote code
execution, so the question is not which algorithm is most elegant but whose
implementation is being trusted. Three candidates were considered.

*A third-party MoonBit package.* Ed25519 implementations exist on Mooncakes at
version 0.x. They are almost certainly unaudited, and Ed25519 verification has a
class of pitfalls — cofactor handling, signature malleability, non-canonical
encodings — that appear only on adversarially constructed input and therefore
survive a green test suite. Rejected.

*Platform verification APIs.* Every target can verify ECDSA P-256 with its own
audited implementation, which would mean writing no cryptography at all. This is
attractive and remains a reasonable alternative. It costs three platform
bindings, a libcrypto dependency on Linux, and a wire format that has to
reconcile CNG's raw `r || s` with Security.framework's and OpenSSL's DER.
Ed25519 is not an option here at all: Windows CNG has supported Curve25519 since
Windows 10, but for ECDH key agreement, not for EdDSA signatures.

*RSA verification written here.* Chosen. Neither the MoonBit core library nor
`moonbitlang/x` provides any asymmetric signature algorithm, so something has to
be written or vendored either way, and RSA verification is the asymmetric
operation that can responsibly be written. It touches no secret data, so it
needs no constant-time discipline. It consumes no randomness. It is modular
exponentiation and a byte comparison, with no curve arithmetic, point
decompression, or cofactor rules. `BigInt::pow(exponent, modulus~)` in the core
library supplies the only hard part. Its one historical pitfall,
Bleichenbacher's 2006 forgery, is defeated structurally rather than carefully:
the verifier rebuilds the encoded block it expects and compares it whole, so
there is no parser to be lenient.

The consequence is that verification stays in MoonBit, works on every backend,
and adds no platform bindings and no native dependency.

### Wire format

A signature is the raw big-endian integer, exactly as long as the modulus — 256
bytes for a 2048-bit key. There is no container and no encoding layer.

Length equality is enforced rather than normalised: a short signature is not
zero-extended and a long one is not trimmed, because accepting several
encodings of one integer is where signature malleability begins. **Nothing in
this design parses attacker-supplied DER**, which is what a container format
would have required.

### Verification input

Signatures are verified over a **digest**, never over a whole artifact.
`verify_pkcs1_sha256` takes the 32-byte SHA-256 produced by streaming the
artifact through `@crypto.sha256`, so a 224 MB download is never held in memory
and never crosses a function boundary as a value.

### Key format

A trusted key carries its algorithm and its parameters, in hexadecimal:

```
rsa-sha256:<modulus hex>:<exponent hex>
```

There is no ASN.1 anywhere in the key path. `proton_cli updater public-key`
converts an OpenSSL public key file into this form.

An unknown algorithm tag is rejected, not guessed. Tagging the algorithm now
means a future migration — to a post-quantum scheme, or away from RSA for any
other reason — does not require a release that existing installations cannot
accept. This is the same forward-compatibility argument as the trusted key
list, and it is equally impossible to retrofit.

Keys are validated when parsed, and the checks are security controls rather
than hygiene: a modulus below 2048 bits verifies signatures perfectly well and
protects nothing; a modulus written with a leading zero byte would let one key
have two spellings with different values of `k`, and `k` decides which signature
lengths are accepted; `e = 1` would make every signature equal to the encoded
block.

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

### Who holds the key

Three parties, and only the first has any key material:

| Party | Provides |
| --- | --- |
| Application developer | Owns the key pair, signs releases, writes the public keys into their `moon.proton` |
| Proton | Nothing. It verifies with the public keys the developer configured |
| End user | Nothing |

**Proton never generates, stores, or transmits a private key**, and the
`proton_cli` surface is deliberately shaped so that it cannot. Developers create
their own key pair with a mature tool:

```sh
openssl genrsa -out updater.pem 2048
openssl rsa -in updater.pem -pubout -out updater.pub
```

`proton_cli` offers only a converter from that public key to the configured
form:

```sh
proton_cli updater public-key updater.pub
# rsa-sha256:94c05429a8686a46...:010001
```

This is a pure data transformation over public material. A `keygen` subcommand
was considered and rejected: generating a private key would oblige Proton to
own a cryptographic random source, to write a secret with the right
permissions, and to keep it out of logs and build output. Tauri has already
shipped a real instance of that last failure, leaking updater private keys
through build-time environment variables. The responsibility is avoidable, so
it is avoided — no secret passes through the framework at any point.

An end user must **not** be able to supply a trusted key. If they could, so
could anything running with their privileges, which would defeat the channel
entirely. This is why the key belongs in the packaged, integrity-protected
bundle rather than anywhere writable such as `app_data_dir()`, and why the
absence of that protection on Windows and Linux is recorded as a limitation.

Key handling:

- One key pair signs both the manifest and the artifacts of a given release. A
  private key never enters the repository and never enters the distribution
  host.
- Signing is performed by OpenSSL, not by any code in this project. Key
  generation and signing are where the operations that must not be improvised
  live, and both stay outside the framework.
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
    "rsa-sha256:94c05429a8686a46...:010001",  // active signer
    "rsa-sha256:b71fe3a20c4d8815...:010001",  // reserve, held offline
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
3. **Download.** Hold the artifact in memory. It is deliberately not written to
   a path chosen before the bytes are trusted: a verified artifact named by a
   path can be swapped between the check and the read, which would spend the
   signature check on one archive and install another.
4. **Verify.** Check `size`, then `sha256`, then the signature over that digest.
   A failure at any step discards the bytes. A partially verified artifact is
   never retained for a later attempt.
5. **Install.** Hand the verified bytes to one native transaction. It creates a
   private directory with `mkdtemp`, unpacks with `ditto`, requires exactly one
   `.app`, validates that bundle's complete code signature and signing identity,
   and then performs the replacement. The expanded path never crosses back to
   MoonBit, so validation cannot be spent on one directory and installation on
   another. The replaced application is retained beside the install location.
6. **Relaunch.** Separate from the swap, because when to restart is a question
   about the user's unsaved work rather than about the update. It reports that
   the request was accepted, which is all the platform will say — see below.

## Native surface

Two functions, following the existing ABI rules: `proton_*` prefix, status
codes, caller-owned error buffers, no platform types across the boundary.

```c
int32_t proton_update_install(const char *archive, int32_t archive_len,
                              const char *parent_dir, char *error,
                              int32_t error_len);
int32_t proton_update_relaunch(char *error, int32_t error_len);
```

Expansion, bundle validation, and replacement deliberately share one call.
Separating validation from replacement by a caller-visible path creates a
time-of-check/time-of-use race: the path can name a different bundle by the time
replacement begins. Relaunch remains separate because the caller owns the
decision about unsaved work and process exit.

Artifact RSA signature verification is **not** here. Choosing RSA kept that in
MoonBit. Native code verifies the expanded bundle's platform code signature,
because that seal is what covers the directory tree after extraction, and owns
the replacement and restart operations. Nothing that decides whether downloaded
bytes are authentic crosses this boundary.

Everything platform-specific lives behind these two. Given that the three
per-platform engine sources are already near-duplicates of one another — a
duplication that has already produced one identical defect in all three copies —
the shared portion belongs in `native/src/engine/cef_common/` from the start
rather than being written three times.

### Per-platform apply

**macOS.** `install` verifies the privately expanded bundle with
`SecStaticCodeCheckValidity` including nested code, then compares its signing
identifier and team identifier with the installed application's, as Sparkle
does; an update signed as a different application or by a different team is
refused before replacement.

How much that establishes depends on how the application is signed. A Developer
ID release carries a team identifier, so the comparison is a real statement
about who produced the update. An ad-hoc signature — what `proton_cli package`
applies when `--sign` is not given — carries no team identifier at all, and two
absent teams compare equal. For those builds this establishes only that the
bundle was not altered after signing and that it calls itself the same
application. That is still the property the local-attacker row needs; it is not
an identity guarantee, and an application that wants one has to ship with a
Developer ID. Swap the bundle with
`rename` on the same volume, then relaunch.

Relaunching cannot be confirmed. `open -n` and `LSOpenFromURLSpec` both return
success once Launch Services accepts the request, and Launch Services decides
afterwards whether to honour it — it declines to start an application under the
per-user temporary directory, for instance, and tells nobody. `relaunch` waits
for `open` so that a missing or malformed bundle is reported rather than
swallowed, and promises nothing beyond that. An application that needs to know
the new version started has to learn it from the new version.

The replaced bundle is kept beside the install location and **never removed**,
so one copy of the application accumulates per update. Bounding that needs a
policy decision — deleting the previous copy once the replacement has started
successfully is the obvious one, and it needs the new version to do the
deleting, because that is the first moment there is evidence worth acting on.
It is not implemented. Two conditions must be reported
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
    "rsa-sha256:94c05429a8686a46...:010001",
    "rsa-sha256:b71fe3a20c4d8815...:010001",
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

*Implemented.* `App::on_update_available` registers the handler; the check runs
from the application task group and calls it with a `PendingUpdate`.

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
  behalf need a way to say so. Registering no handler disables it too: an
  application with nothing to do about an update is not asked to go and find
  one.

Finding an update does **not** start a download and does not apply anything. The
runtime reports availability; the application decides what to do with it. The
distinction matters: automatic *checking* is a reasonable default, whereas
automatic *installing* changes the code a user is running without their consent
and is not something a framework should decide for every application.

## Renderer surface

*Implemented* as the `justjavac/proton-updater` extension, in the `updater`
namespace. Update capability is exposed through the existing permission model.
Registration alone grants nothing; a window needs an explicit grant.

- `updater.check` — returns `not_configured`, `up_to_date`, or `available` with
  the version, notes URL and size.
- `updater.download` — downloads and installs what the last `check` found, and
  reports progress through `window.__MoonBit__.updater.on("progress", ...)`.
- Restarting is **not** a renderer capability. Deciding when to interrupt
  someone belongs to the application.

**Neither op takes an argument.** That is the mechanism, not an accident of the
schema: a page that could name an endpoint, a version, or a path would hold a
remote code execution primitive over the host. `download` installs whatever the
host already authenticated, or refuses. Everything it acts on comes from
`moon.proton` and the signed manifest.

The extension is not in `@ext.all()` or `@ext.desktop()`. An application asking
for "the built-in extensions" should not thereby hand its pages the ability to
replace it; registering this one is a separate decision.

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
key held as a secret — never as part of an ordinary build, and never through
Proton. `proton_cli package` emits the artifact and the digest to be signed;
producing the signature is an OpenSSL invocation the developer controls.

Merging per-platform fragments into one manifest is a separate step because the
three platforms are built on three machines, which is already true of
`proton/prebuilt/`.

## Failure handling

- Any verification failure aborts and deletes the private install transaction.
  The running application is never modified.
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
- **Dev runs never check.** A development run is not inside an installed
  bundle, so there is nothing an update could replace.

## Phasing

1. Manifest schema, key generation, signing, and `proton_cli` emission. This is
   independently testable and is the input to everything else.
2. MoonBit check, download, and verification, with no apply step. The update can
   be observed and validated end to end without ever modifying an installation.
3. macOS apply and relaunch.
4. Windows and Linux, after their installers exist.

## Open questions

- **Documenting reserve key custody.** A trusted list is only useful if the
  reserve key is stored somewhere the compromise of the active key does not
  reach. That custody decision belongs to each application developer, not to
  Proton, so the open question is how much guidance the documentation should
  offer without appearing to take on a responsibility the framework has
  deliberately declined.
- **Freshness window default.** Thirty days is a placeholder. Too short and a
  quiet project locks its own users out of updating; too long and a pinning
  attacker gets a wide window.
- **Sequencing against a Proton runtime bump.** An application update that also
  changes the CEF version transfers the whole framework. Version 1 accepts that,
  but it is the point where the layered scheme stops being an optimisation and
  starts being necessary.
