///|
/// Command-line package metadata shared by `proton_package` and higher-level
/// packaging frontends.
pub(all) struct PackageArguments {
  product_name : String?
  identifier : String?
  version : String?
  formats : Array[@package.PackageFormat]
  output : String?
  icons : Array[String]
  url_schemes : Array[String]
  sign : Bool
  notarize : Bool
} derive(Debug, Eq)

///|
pub extend PackageArguments with Eq::{not_equal, equal}

///|
pub extend PackageArguments with Debug::{to_repr}

///|
/// Returns the package flags shared by command-line packaging frontends.
pub fn flags() -> Array[@argparse.FlagArg] {
  [
    FlagArg("sign", about="Sign the packaged application"),
    FlagArg("notarize", about="Sign, notarize, and staple a macOS application"),
  ]
}

///|
/// Returns the package options shared by command-line packaging frontends.
pub fn options(include_identifier? : Bool = true) -> Array[@argparse.OptionArg] {
  let options : Array[@argparse.OptionArg] = [
    OptionArg("product-name", about="Application display name"),
    OptionArg("version", about="Application version"),
    OptionArg(
      "format",
      action=Append,
      about="Output format: app, zip, dmg, nsis, or appimage; may be repeated",
    ),
    OptionArg("output", about="Artifact output directory"),
    OptionArg("icon", action=Append, about="Platform icon; may be repeated"),
    OptionArg(
      "url-scheme",
      action=Append,
      about="Registered URL scheme; may be repeated",
    ),
  ]
  if include_identifier {
    options.insert(
      1,
      OptionArg("identifier", about="Reverse-DNS application identifier"),
    )
  }
  options
}

///|
/// Decodes the shared package arguments from parsed command matches.
pub fn from_matches(
  matches : @argparse.Matches,
) -> PackageArguments raise @package.PackagePlanError {
  PackageArguments::{
    product_name: first(matches.values, "product-name"),
    identifier: first(matches.values, "identifier"),
    version: first(matches.values, "version"),
    formats: values(matches.values, "format").map(value => {
      @package.PackageFormat::parse(value)
    }),
    output: first(matches.values, "output"),
    icons: values(matches.values, "icon"),
    url_schemes: values(matches.values, "url-scheme"),
    sign: matches.flags.get("sign").unwrap_or(false) ||
    matches.flags.get("notarize").unwrap_or(false),
    notarize: matches.flags.get("notarize").unwrap_or(false),
  }
}

///|
fn first(values : Map[String, Array[String]], name : String) -> String? {
  match values.get(name) {
    Some([value, ..]) => Some(value)
    _ => None
  }
}

///|
fn values(values : Map[String, Array[String]], name : String) -> Array[String] {
  values.get(name).unwrap_or([])
}
