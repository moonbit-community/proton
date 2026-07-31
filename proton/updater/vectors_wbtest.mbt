// Vectors signed with the same OpenSSL key `justjavac/proton_rsa` uses. The
// manifest signature covers the manifest bytes exactly as transmitted, and the
// artifact signature covers the artifact bytes; both were produced by OpenSSL,
// so a disagreement indicts this package rather than the vector.

///|
let vector_modulus_hex : String = "94c05429a8686a468bd96483217aaa1615c8785c43b42a6353e7b45ebbc847a5aab1cdb55493720ec1110d20c765bbf03f32a5c77da79c467f4763cec4b4ea8c0d589994a263955c3739994e34bf5d645ded04a75ad1ccbd64e9f686101d682744352d233e70a8674b1a8ffe0f940777ed6f43830c8758aa5cfaa185b44ef35f4bf0391999440e52f008aa58d4be711ddac72124b81303b6e5de80075300aeff22519559c32d29328622a8ac4498cc080bab09f3c15bed4b0c561f55720fd39157f37ece0f9250ecdf6e3049038770bb9f088e5f3cdeaf44de70e9808386c15cc76da86e6842aaeda8d39c0c8b36a4c2f972c00f62a7f559c6b22de5f602a45d"

///|
let vector_manifest : String = "{\"schema_version\":1,\"version\":\"0.3.0\",\"published_at\":\"2026-08-01T00:00:00Z\",\"notes_url\":\"https://example.com/notes\",\"platforms\":{\"darwin-arm64\":{\"kind\":\"full\",\"url\":\"https://example.com/App-0.3.0.zip\",\"size\":11,\"sha256\":\"4c83048dd991da670e578ca812c1b6a306dc69ee8c389d2a2e41f0de4595881c\",\"signature\":\"57001d17e8d680de1274b3fc8fb8bb7fe54d5fdd77b92bf592f9725bc3efd6d76281843394f170e9c9b38477ba5d2e005ea406bcdc98d8130f5564af6f62ae05c83f8f6655d387cc0511bb54d5e0f910f36ee5f1f4392099034e32a9664076a512e862210963bf76b1b60ad9aee4f9b0101423cf11bdf0919697799273e0f9372e86f08910f22196ee225955edd299277436c79fe4f07db5bb4195139c98c95930fd10d8e885bf413441bde51b82979959a7f82903fb3a55eee418576d303db2a7348cfd5d664a6c5ebd4e474f112263244dd75d78a8a82f2807aa2f9d59c258f62a8671c5cb239e707d087b59330ddce892b7c3ddaa228c552b90bda636cd10\"}}}"

///|
let vector_manifest_signature_hex : String = "38e53b6edeb5956b5b6f01fa72a45348c4167068e2877b94c4b917edd06d2866f6be2cfee18a1c5982d9b2f5921c54da52a7a1bc12dd2ccfa19a2bb22066f359ac14a3aaf0e5b139a6142243141b672b8ed4fee2641e8e1572cd4c8be4716ff79f48415a30be39ae1cb0976cb249c3acdf7ae96f563882d0e921896d11888921affd5af22c8f4117c72c62b2021e009d9d85b057c0aac54af85b8ee1ce4ca2e74be54158ec7f0296a182c6b4f1dcf851f263025e4473d8bd69c7a1eb93c9d9432151d9a13a7e117ec87708eb485528c2ba38da813c786b275838f54468a1366be7cb1e3147203a6a8b5fb6d278f8f89926f7c7e67e726c2d3b7514f0a36eaebe"

///|
let vector_artifact : Bytes = b"proton zip\n"

///|
let vector_artifact_sha256_hex : String = "4c83048dd991da670e578ca812c1b6a306dc69ee8c389d2a2e41f0de4595881c"
