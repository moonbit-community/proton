# moonbit-community/proton_rsa

RSASSA-PKCS1-v1_5 signature verification over SHA-256, in pure MoonBit.

This package exists to verify Proton update manifests and artifacts. It is the
single point at which an application decides whether foreign code is allowed to
run, so it is deliberately small enough to read in full.

## Scope

Verification only. There is no key generation and no signing: those happen once
per release on a maintainer machine, where a mature tool such as OpenSSL is
available and appropriate. Signing is also where RSA's genuinely dangerous
operations live — a reused or biased nonce in other schemes, private key
handling here — and none of that belongs in code that ships to users.

Only SHA-256 is supported. A verifier that accepts several digest algorithms has
to decide which ones remain acceptable over time, and that decision is easier to
get wrong than to leave out.

## Use

```moonbit nocheck
let key = @rsa.PublicKey::parse("rsa-sha256:<modulus hex>:<exponent hex>")
let digest = compute_sha256_of_the_artifact()
if @rsa.verify_pkcs1_sha256(key, digest, signature) {
  // The signature is valid.
}
```

`verify_pkcs1_sha256` takes a digest rather than the signed content, so a large
artifact can be streamed through a hash instead of being held in memory.

## Properties this package relies on

**Verification returns a boolean and never raises.** A caller that could
distinguish "invalid signature" from "failed to check the signature" would
eventually treat one as the other. Every rejection — wrong length, a signature
not below the modulus, malformed padding, the wrong digest — is `false`. MoonBit
refuses to implicitly discard a non-unit result, so the answer cannot be ignored
by accident.

**The encoded block is rebuilt and compared, never parsed.** Verification
constructs the block that a valid signature must decrypt to and compares it in
full. It never walks the padding looking for the digest. This is what defeats
Bleichenbacher's 2006 forgery, which works against verifiers that scan for the
`DigestInfo` and ignore whatever follows it. `forgery_wbtest.mbt` signs exactly
such a block with the test key and asserts that it is rejected.

**Signature length must equal the modulus length.** A shorter signature is not
zero-extended and a longer one is not trimmed, because accepting several
encodings of one integer is where signature malleability begins.

**`I2OSP` is length-checked.** `BigInt::to_octets(length=)` left-pads a short
value but does not truncate a long one, so the returned length is the only
reliable evidence that a value fits in `k` bytes. Verification checks it.

**Keys are validated when parsed.** A modulus below 2048 bits is refused; so is
a modulus written with a leading zero byte, because that would let two different
texts denote the same key with different values of `k`. An exponent below 3, an
even exponent, or one not smaller than the modulus is refused. `e = 1` would
make every signature equal to the encoded block.

**Comparison does not exit early.** Everything compared is public, so timing
leaks nothing here; the routine is written this way so that it does not become a
vulnerability if it is ever reused on secret data.

## Test vectors

`vectors_wbtest.mbt` holds a key and signature produced by OpenSSL, which also
verifies them. A disagreement is therefore a defect in this package.

`forgery_wbtest.mbt` holds signatures crafted with that key's private exponent,
each chosen so that it decrypts to a specific malformed block: padding cut short
with trailing data, a missing leading zero, the wrong block type, a padding octet
that is not `0xFF`, a missing separator, a `DigestInfo` naming SHA-1, and a well
formed block for a different digest. An ordinary wrong signature decrypts to
noise and is rejected long before block structure matters, so these are the only
inputs that exercise the padding check at all.

## What this package does not defend against

It verifies a signature against a key it is given. It has nothing to say about
where that key came from, whether the key is still trusted, or whether the
signed version is newer than the running one. Key custody, rotation, and
rollback protection belong to the caller.
