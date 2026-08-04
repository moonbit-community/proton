// Test vectors produced with OpenSSL, not by this package:
//
//   openssl genrsa -out key.pem 2048
//   printf 'proton updater test vector' > msg.bin
//   openssl dgst -sha256 -sign key.pem -out sig.bin msg.bin
//
// OpenSSL verifies this signature against the same key, so a disagreement here
// is a defect in this package rather than in the vector. The values are single
// lines because the decoder rejects whitespace on purpose.

///|
let vector_modulus_hex : String = "94c05429a8686a468bd96483217aaa1615c8785c43b42a6353e7b45ebbc847a5aab1cdb55493720ec1110d20c765bbf03f32a5c77da79c467f4763cec4b4ea8c0d589994a263955c3739994e34bf5d645ded04a75ad1ccbd64e9f686101d682744352d233e70a8674b1a8ffe0f940777ed6f43830c8758aa5cfaa185b44ef35f4bf0391999440e52f008aa58d4be711ddac72124b81303b6e5de80075300aeff22519559c32d29328622a8ac4498cc080bab09f3c15bed4b0c561f55720fd39157f37ece0f9250ecdf6e3049038770bb9f088e5f3cdeaf44de70e9808386c15cc76da86e6842aaeda8d39c0c8b36a4c2f972c00f62a7f559c6b22de5f602a45d"

///|
let vector_exponent_hex : String = "010001"

///|
let vector_digest_hex : String = "ea44eebe5feee64a9e25e1d19298acc7944521397869b9e7cf170de0e625fc89"

///|
let vector_signature_hex : String = "3e23cf2dff913700f499d4f5904347139cc38dc5bf55f9bd4552d5ef2e4525bb1587e463edbf4a1c26deb67bcdb144e1aec25ff6393bde22a2cf43d6fa3c07803479b6144f35ff52ea55ac082f925eb93e5ff06061c873b2bd6109bef5d26856196e9d030ec7c2c7ee8ee56bc8ec483f026c4f43fbf833581e9565fba5a84a0a4d9dac01b410e1f3cf4a7c00b2c34fd910643aa767e6032b351ce8a7796e0b25ef5eafa9adb9337e68381a6d35c3b5f8590529ad749399e5325eb7ab30513b505c87a2dacdcb89231f95e58c57f40b0dedb676f379a6a2098e3fe363f383502623e17c8700f01168de919856c116787f78a85d7efa3b1798c62e1265beb67b19"
