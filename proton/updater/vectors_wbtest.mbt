// Vectors signed with an ephemeral OpenSSL RSA-2048 test key. The
// manifest signature covers the manifest bytes exactly as transmitted, and the
// artifact signature covers the artifact bytes; both were produced by OpenSSL,
// so a disagreement indicts this package rather than the vector.

///|
let vector_modulus_hex : String = "ce78ad25bc9617215ecbc56a303330acbbc9c39da56bac8b6cd6379996c0565d6a4fd4e4463d5ab23facb82e7d110ab8389713ae08eab5fdba9594ccfc036f5c3a2675a217fb5f2ebd4d1967012e0f8ac066a2fbf866bce97f3c6ca93f991718a4f9b6b1480b0a8907818405bc91699612cb06db9e44af581a1c65b0cd49b5acde109b0892067a2fa1356f28ab71597baead105e46031f4a6561bf2be9afeba6a9950ad08dcf4ab31a902a632d8d33d13eb4bb5e82ce21813290796dc50f806d9844b91bea5eedb5ad13fe20193e4ddce9ab59a7365c92cedb3e15eec2d9692bb337af93c9827c285ae9716c5dee1a43253972f1f73fec0e8a442068b83824e7"

///|
let vector_manifest : String = "{\"schema_version\":3,\"version\":\"0.3.0\",\"published_at\":\"2026-08-01T00:00:00Z\",\"notes_url\":\"https://example.com/notes\",\"platforms\":{\"darwin-arm64\":{\"kind\":\"full\",\"url\":\"https://example.com/App-0.3.0.zip\",\"size\":11,\"sha256\":\"4c83048dd991da670e578ca812c1b6a306dc69ee8c389d2a2e41f0de4595881c\",\"signature\":\"37fad03e1296d047b5d85ac66c23c4f83b3b8df44a5f55909b05b6744c77728c39b4bf6e197b53c6656e31dfb70bf1f9b1d26b89ac5f84dd61977352a56f27ba2e7bfe03b9754acda591f9fcac999a2a328692ca53ad823c2bfe2664ccf4758e78bc5113cb99619a4e95c3eccaa8b51eb5b724057f3d656d7d303030ff988cdfd7f52caee686d098e63b2b9eb37ec7929dc386c1e2b7a771a76c7f7d4d1d28106a7169785d417775309650e3f03e7c8f6fb675ae4032a1f76d48e738b5557df8bd86854db278ea7154993b062b4802a9136896ecfdca3256e2fb5f112d826eea4ce3712a64a8bbffaff302ccbc324c0e03642cd697ad68b4144742e757aec95e\"}}}"

///|
let vector_manifest_signature_hex : String = "c91925da49b5e93096dac37b2faf8cae436fd3a76b36a3a113f0c56879ea93203c5d3c75ddbdd9b8012163e886ec5a821b4d551387ca34d3eb0133089b04dd473bfa276df2581d2a50102b2cee08af71fc6806c950425af097a0c6669bc8319b8694d29e9df6337c551c57a4a3d49a6cd00e298bb01309191fd27279b9d30d1b5b7cb0f17774d7ac8152e26c43cd2bc626981cc75cb6c587ae7f0c48a9c97be73e74e7b33c9e58b6d07a0e9dd98b32e0d3356fbf7b3ce12036a57ee1af7bdecc8a1896548a0d7385bb8f4be83f3daababc168b4378a54f470712f75065a107e27c932eada050b497845c2843b88ec63b03ab8d5b59376350b2889bb71ad031ce"

///|
let vector_artifact : Bytes = b"proton zip\n"

///|
let vector_artifact_sha256_hex : String = "4c83048dd991da670e578ca812c1b6a306dc69ee8c389d2a2e41f0de4595881c"
