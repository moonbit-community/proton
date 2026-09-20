# moonbit-community/proton_rsa

RSASSA-PKCS1-v1_5 signature verification over SHA-256, in pure MoonBit.

This package exists to verify Proton update manifests and artifacts.

## Scope

Verification only, using SHA-256. Key generation and signing are not provided.

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

## Validation

Verification returns `false` for invalid signatures. Signature length must equal
the modulus length. Public keys require a modulus of at least 2048 bits without
a leading zero byte and an odd exponent of at least 3, smaller than the modulus.

## Trust

It verifies a signature against a key it is given. It has nothing to say about
where that key came from, whether the key is still trusted, or whether the
signed version is newer than the running one. Key custody, rotation, and
rollback protection belong to the caller.
