///|
/// A trusted public key could not be decoded.
///
/// Every variant describes a defect in configuration, not in a signature.
/// Signature verification itself never raises: it answers with a boolean, so
/// that no caller can mistake an error path for a successful check.
pub(all) suberror KeyError {
  UnknownAlgorithm(tag~ : String)
  Malformed(detail~ : String)
  NonCanonicalModulus
  ModulusTooSmall(bits~ : Int, minimum~ : Int)
  InvalidExponent(detail~ : String)
} derive(Debug, Eq)

///|
pub fn KeyError::message(self : KeyError) -> String {
  match self {
    UnknownAlgorithm(tag~) => "unknown public key algorithm: \{tag}"
    Malformed(detail~) => "malformed public key: \{detail}"
    NonCanonicalModulus =>
      "public key modulus must not have a leading zero byte"
    ModulusTooSmall(bits~, minimum~) =>
      "public key modulus is \{bits} bits, minimum is \{minimum}"
    InvalidExponent(detail~) => "invalid public exponent: \{detail}"
  }
}

///|
impl Show for KeyError with fn output(self, logger) {
  logger.write_string(self.message())
}
