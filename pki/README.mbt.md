# moonbit-community/proton_pki

`parse_rsa_public_key(pem)` reads one PEM-encoded RSA public key and returns
its modulus and public exponent, in that order. It accepts PKCS#1
(`RSA PUBLIC KEY`) and SubjectPublicKeyInfo (`PUBLIC KEY`) with the
`rsaEncryption` algorithm identifier and NULL parameters.

The parser checks the key encoding. The caller owns RSA key policy, including
minimum modulus size and permitted exponents. Proton's updater applies this
policy through `moonbit-community/proton_rsa`.
