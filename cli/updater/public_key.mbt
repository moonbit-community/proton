///|
/// Returns the declarative `proton_cli updater` command specification.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "updater",
    about="Prepare Proton update metadata",
    subcommands=[public_key_command()],
    subcommand_required=true,
  )
}

///|
fn public_key_command() -> @argparse.Command {
  @argparse.Command(
    "public-key",
    about="Format and validate a trusted updater public key",
    options=[
      OptionArg("modulus", about="RSA modulus in hexadecimal"),
      OptionArg(
        "exponent",
        default_values=["010001"],
        about="RSA public exponent in hexadecimal",
      ),
    ],
  )
}

///|
/// A public key could not be assembled from the given arguments.
pub(all) suberror UpdaterUsageError {
  MissingModulus
  RejectedKey(detail~ : String)
} derive(Debug, Eq)

///|
pub extend UpdaterUsageError with Eq::{not_equal, equal}

///|
pub extend UpdaterUsageError with Debug::{to_repr}

///|
pub extend UpdaterUsageError with Show::{to_string, output}

///|
pub fn UpdaterUsageError::message(self : UpdaterUsageError) -> String {
  match self {
    MissingModulus =>
      (
        $|--modulus is required
        $|
        $|Obtain it from an OpenSSL private or public key:
        $|  openssl rsa -in updater.pem -noout -modulus
      )
    RejectedKey(detail~) => detail
  }
}

///|
impl Show for UpdaterUsageError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
/// Runs a parsed updater subcommand.
pub fn run(matches : @argparse.Matches) -> Unit raise UpdaterUsageError {
  match matches.subcommand {
    Some(("public-key", key_matches)) => println(public_key(key_matches))
    _ => abort("argparse invariant violated: missing updater subcommand")
  }
}

///|
/// Builds the configured form of a trusted public key.
///
/// This command deliberately does not read a PEM file. Extracting the modulus
/// from one means parsing ASN.1, and the verification path in
/// `moonbit-community/proton_rsa` was written specifically to contain no ASN.1 parser
/// at all. OpenSSL already prints the modulus directly, so adding a parser here
/// would take on that risk to save one shell command.
fn public_key(matches : @argparse.Matches) -> String raise UpdaterUsageError {
  guard matches.values
    is {
      "modulus": [modulus, ..],
      "exponent"? : Some([exponent, ..])
      | (_ with exponent = "010001"),
      ..
    } else {
    raise MissingModulus
  }
  let modulus = normalize_hex(modulus)
  let exponent = normalize_hex(exponent)
  let text = "rsa-sha256:\{modulus}:\{exponent}"
  // Parsing is the validation. Every rule the runtime will apply to this key —
  // minimum modulus size, canonical encoding, a usable exponent — is enforced
  // here, so a key that prints is a key the runtime will accept.
  let key = @rsa.PublicKey::parse(text) catch {
    error => raise RejectedKey(detail=error.message())
  }
  println(
    "# \{key.bits()}-bit RSA, add to proton.project.json updater.public_keys",
  )
  text
}

///|
/// Lowercases a hexadecimal argument and strips the `Modulus=` prefix that
/// `openssl rsa -noout -modulus` prints, so its output can be pasted whole.
fn normalize_hex(value : String) -> String {
  let trimmed = match value.strip_prefix("Modulus=") {
    Some(rest) => rest.to_owned()
    None => value
  }
  trimmed.trim(chars=" \t\r\n").to_owned().to_lower()
}
