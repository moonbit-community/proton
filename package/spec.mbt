///|
async fn package_spec(matches : @argparse.Matches) -> @package.PackageSpec {
  let (config, base) = match option(matches, "config") {
    Some(path) => load_package_config(path)
    None => ((Default::default() : PackageConfig), ".")
  }
  let arguments = @package_args.from_matches(matches)
  let executable = prefer(
    option(matches, "executable"),
    config.executable.map(path => resolve_path(base, path)),
  )
  let output = prefer(
    arguments.output,
    config.output.map(path => resolve_path(base, path)),
  ).unwrap_or("dist")
  let formats = if arguments.formats.is_empty() {
    config.formats.unwrap_or([]).map(@package.PackageFormat::parse)
  } else {
    arguments.formats
  }
  let icons = if arguments.icons.is_empty() {
    config.icons.unwrap_or([]).map(path => resolve_path(base, path))
  } else {
    arguments.icons.map(path => @path.Path(path).resolve().to_string())
  }
  let url_schemes = if arguments.url_schemes.is_empty() {
    config.url_schemes.unwrap_or([])
  } else {
    arguments.url_schemes
  }
  @package.PackageSpec(
    @path.Path(required(executable, "executable")).resolve().to_string(),
    required(
      prefer(arguments.product_name, config.product_name),
      "product-name",
    ),
    required(prefer(arguments.identifier, config.identifier), "identifier"),
    required(prefer(arguments.version, config.version), "version"),
    formats,
    @path.Path(output).resolve().to_string(),
    payloads=config.payload_specs(base),
    icons~,
    url_schemes~,
    document_types=config.document_type_specs(),
    sign=arguments.sign || config.sign.unwrap_or(false),
    notarize=arguments.notarize || config.notarize.unwrap_or(false),
  )
}

///|
fn option(matches : @argparse.Matches, name : String) -> String? {
  match matches.values.get(name) {
    Some([value, ..]) => Some(value)
    _ => None
  }
}

///|
fn prefer(primary : String?, fallback : String?) -> String? {
  match primary {
    Some(value) => Some(value)
    None => fallback
  }
}

///|
fn required(value : String?, name : String) -> String raise PackageCommandError {
  match value {
    Some(value) => value
    None => raise PackageCommandError::MissingOption(name~)
  }
}
