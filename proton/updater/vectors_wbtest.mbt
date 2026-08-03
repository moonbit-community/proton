// Vectors signed with the same OpenSSL key `justjavac/proton_rsa` uses. The
// manifest signature covers the manifest bytes exactly as transmitted, and the
// artifact signature covers the artifact bytes; both were produced by OpenSSL,
// so a disagreement indicts this package rather than the vector.

///|
let vector_modulus_hex : String = "af3280b035dade3695cc47ba3ae40bab339b2e2059610449e05d49d73a1f211bd09c1ccbaac5c365c46b8f87345c75932053cda0c09777e78c039bdd8a269082ceb45b04e0c32bdd76ce1370b5caf66a86a5049adab1c4bdd96357cb018db43b8734adc69ecf71ff4416d1060564a57025ca35b471ad23a55f7933a8503098cf0efb72074ecada34b8dfd37b9bff0880152dbcbc03ce6c09a06eae526c89781645a93760ab318672651002e741f7b05f68c41b9ba31cc118f9d82cb5e23f7a08602c64bf6f4bc5a09ea3b4d011f30bb87002f577322033f8999ccf8ae272f04dd27a4021c8d296c48dd93fce6b59b230576aab4608963a46a6eb241739ca7771"

///|
let vector_manifest : String = "{\"schema_version\":2,\"version\":\"0.3.0\",\"revision\":3,\"published_at\":\"2026-08-01T00:00:00Z\",\"notes_url\":\"https://example.com/notes\",\"platforms\":{\"darwin-arm64\":{\"kind\":\"full\",\"url\":\"https://example.com/App-0.3.0.zip\",\"size\":11,\"sha256\":\"4c83048dd991da670e578ca812c1b6a306dc69ee8c389d2a2e41f0de4595881c\",\"signature\":\"0cf14fd140263c03349c0efde077d3f06ace533524c65705c8de3bf36f27b3c097b043891424f6c9eacb08c489da309cca2b94eb1134e4f8f9217a3da2917b1bd4dbd905144c178a8a97157ea6db9839675d50fdab8d7a3bec2c285d181915eb2ac2c0abd4c32cd79bed497be6417ec9b497218609a38db9867caa56f1040ea9b800ef0961486eec3fea4f4c1b09976aa84c5911683556dd42c8a20812c851173689b5f9a5ee646b685d30a9694d32db03c6f18fdf2794d1df8003d92b9b33d974e936f9b3e35d3bb5697314ccadfa4db98526477df0003b14608a1a5cf4901b2e8f0255c41c778f6003f74c3d65ce1ceda5f08fe2a190937da999a17a0dfa19\"}}}"

///|
let vector_manifest_signature_hex : String = "5e2e83ab768602da8032d70a5d73d7bd5acd473c3a0161da0df67c308987b3f43cf5dd5906adf0c481a26bb9e0afb66770385afca4749926e0505bc7c85dc5a23cd79ba9afe6037678a7598028f204a5625b71843d121353edba2258a50da480fafc1a1f7f03685266bf235ed531930044b80365b0a316c287e1c521ccfbc265c95c36f1b9eb598c1d7faa24aea63a0adf57b8838c2f0729ad5685cc0964815f31d5d5767403812c69d43b1da5b365d19c808185b02b8b0a2c7248bef3168958de33542a21ba95d8a81d95a5aedba0933d5898cad8ec914f0dad6ab0b9d09cb21de0a9821ee9dea75f672419f95992ddbd2ab9567049fe1cdf2c3713e391c378"

///|
let vector_artifact : Bytes = b"proton zip\n"

///|
let vector_artifact_sha256_hex : String = "4c83048dd991da670e578ca812c1b6a306dc69ee8c389d2a2e41f0de4595881c"
