///|
/// A real 2048-bit modulus, from the same OpenSSL key the `moonbit-community/proton_rsa`
/// vectors use.
let sample_modulus : String = "94c05429a8686a468bd96483217aaa1615c8785c43b42a6353e7b45ebbc847a5aab1cdb55493720ec1110d20c765bbf03f32a5c77da79c467f4763cec4b4ea8c0d589994a263955c3739994e34bf5d645ded04a75ad1ccbd64e9f686101d682744352d233e70a8674b1a8ffe0f940777ed6f43830c8758aa5cfaa185b44ef35f4bf0391999440e52f008aa58d4be711ddac72124b81303b6e5de80075300aeff22519559c32d29328622a8ac4498cc080bab09f3c15bed4b0c561f55720fd39157f37ece0f9250ecdf6e3049038770bb9f088e5f3cdeaf44de70e9808386c15cc76da86e6842aaeda8d39c0c8b36a4c2f972c00f62a7f559c6b22de5f602a45d"

///|
fn parse_arguments(arguments : Array[String]) -> @argparse.Matches raise {
  command().parse(argv=arguments, env=Map([])).subcommand.unwrap().1
}

///|
fn key_for(arguments : Array[String]) -> String raise {
  public_key(parse_arguments(arguments))
}

///|
fn key_failure(arguments : Array[String]) -> UpdaterUsageError raise {
  // Parse first, so the catch below binds the command's own error type rather
  // than argparse's.
  let matches = parse_arguments(arguments)
  let _ = public_key(matches) catch { error => return error }
  abort("expected the key to be rejected")
}

///|
test "formats a valid key with the default exponent" {
  assert_eq(
    key_for(["public-key", "--modulus", sample_modulus]),
    "rsa-sha256:\{sample_modulus}:010001",
  )
}

///|
test "accepts the output of openssl rsa -noout -modulus verbatim" {
  // Uppercase, with the prefix OpenSSL prints, so the line can be pasted whole.
  assert_eq(
    key_for(["public-key", "--modulus", "Modulus=\{sample_modulus.to_upper()}"]),
    "rsa-sha256:\{sample_modulus}:010001",
  )
  assert_eq(
    key_for(["public-key", "--modulus", "  \{sample_modulus}\n"]),
    "rsa-sha256:\{sample_modulus}:010001",
  )
}

///|
test "carries an explicit exponent through" {
  assert_eq(
    key_for([
      "public-key", "--modulus", sample_modulus, "--exponent", "0100000001",
    ]),
    "rsa-sha256:\{sample_modulus}:0100000001",
  )
}

///|
test "requires a modulus" {
  assert_eq(key_failure(["public-key"]), MissingModulus)
}

///|
test "refuses a key the runtime would refuse" {
  // Validation is delegated to the same parser the runtime uses, so anything
  // this command prints is a key the runtime will accept. A 1024-bit modulus,
  // a leading zero byte, and an unusable exponent each fail here.
  assert_true(
    key_failure(["public-key", "--modulus", "c" + "0".repeat(255)])
    is RejectedKey(_),
  )
  assert_true(
    key_failure(["public-key", "--modulus", "00\{sample_modulus}"])
    is RejectedKey(_),
  )
  assert_true(
    key_failure(["public-key", "--modulus", sample_modulus, "--exponent", "01"])
    is RejectedKey(_),
  )
  assert_true(
    key_failure([
      "public-key", "--modulus", sample_modulus, "--exponent", "010002",
    ])
    is RejectedKey(_),
  )
  assert_true(
    key_failure(["public-key", "--modulus", "zz\{sample_modulus}"])
    is RejectedKey(_),
  )
}
