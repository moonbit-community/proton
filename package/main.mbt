///|
priv struct RawConfig {
  executable : String?
  product_name : String?
  identifier : String?
  version : String?
  formats : Array[String]
  output : String?
  payloads : Array[@package.Payload]
  icons : Array[String]
  url_schemes : Array[String]
  document_types : Array[@package.DocumentType]
  sign : Bool
  notarize : Bool
}

///|
fn empty_config() -> RawConfig {
  RawConfig::{
    executable: None,
    product_name: None,
    identifier: None,
    version: None,
    formats: [],
    output: None,
    payloads: [],
    icons: [],
    url_schemes: [],
    document_types: [],
    sign: false,
    notarize: false,
  }
}

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "proton_package",
    about="Package an already-built desktop executable",
    flags=[
      FlagArg("sign", about="Sign the packaged application"),
      FlagArg("notarize", about="Sign and notarize a macOS application"),
    ],
    options=[
      OptionArg("config", about="JSON package specification"),
      OptionArg("executable", about="Already-built application executable"),
      OptionArg("product-name", about="Application display name"),
      OptionArg("identifier", about="Reverse-DNS application identifier"),
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
    ],
  )
}

///|
fn string_field(fields : Map[String, Json], name : String) -> String? {
  match fields.get(name) {
    Some(String(value)) => Some(value)
    Some(_) => abort("package config field " + name + " must be a string")
    None => None
  }
}

///|
fn bool_field(fields : Map[String, Json], name : String) -> Bool {
  match fields.get(name) {
    Some(True) => true
    Some(False) | None => false
    Some(_) => abort("package config field " + name + " must be a boolean")
  }
}

///|
fn string_array_field(
  fields : Map[String, Json],
  name : String,
) -> Array[String] {
  match fields.get(name) {
    None => []
    Some(Array(values)) =>
      values.map(fn(value) {
        match value {
          String(value) => value
          _ => abort("package config field " + name + " must contain strings")
        }
      })
    Some(_) => abort("package config field " + name + " must be an array")
  }
}

///|
fn resolve_config_path(base : String, value : String) -> String {
  let path : @path.Path = value
  if path.is_absolute() {
    path.resolve().to_string()
  } else {
    @path.Path(base).join(path).resolve().to_string()
  }
}

///|
fn payloads_field(
  fields : Map[String, Json],
  base : String,
) -> Array[@package.Payload] raise @package.PackagePlanError {
  guard fields.get("payloads") is Some(Array(values)) else { return [] }
  values.map(value => {
    guard value is Object(payload) else {
      abort("package config payload must be an object")
    }
    guard payload
      is { "source": String(source), "destination": String(destination), .. } else {
      abort("package config payload requires source and destination strings")
    }
    let location = match payload.get("location") {
      Some(String(value)) => @package.PayloadLocation::parse(value)
      None => @package.PayloadLocation::Resources
      Some(_) => abort("package config payload location must be a string")
    }
    @package.Payload::new(
      resolve_config_path(base, source),
      destination,
      location~,
    )
  })
}

///|
fn document_types_field(
  fields : Map[String, Json],
) -> Array[@package.DocumentType] {
  guard fields.get("document_types") is Some(Array(values)) else { return [] }
  values.map(fn(value) {
    guard value is Object(document_type) else {
      abort("package config document_type must be an object")
    }
    guard document_type
      is { "name": String(name), "extensions": Array(extension_values), .. } else {
      abort("package config document_type requires name and extensions")
    }
    let extensions = extension_values.map(fn(value) {
      match value {
        String(value) => value
        _ => abort("document_type extensions must contain strings")
      }
    })
    let role = match document_type.get("role") {
      Some(String(role)) => role
      None => "Viewer"
      Some(_) => abort("document_type role must be a string")
    }
    @package.DocumentType::new(name, extensions, role~)
  })
}

///|
async fn read_config(path : String) -> RawConfig {
  let absolute = @path.Path(path).resolve()
  let text = @async_fs.read_file(absolute.to_string()).text() catch {
    error =>
      abort("failed to read package config: " + @debug.render(Repr(error)))
  }
  let json = @json.parse(text) catch {
    error => abort("invalid package config JSON: " + @debug.render(Repr(error)))
  }
  guard json is Object(fields) else {
    abort("package config root must be an object")
  }
  guard fields.get("schema_version") is Some(Number(1.0, ..)) else {
    abort("package config requires schema_version 1")
  }
  let base = absolute.dirname().to_string()
  RawConfig::{
    executable: string_field(fields, "executable").map(fn(path) {
      resolve_config_path(base, path)
    }),
    product_name: string_field(fields, "product_name"),
    identifier: string_field(fields, "identifier"),
    version: string_field(fields, "version"),
    formats: string_array_field(fields, "formats"),
    output: string_field(fields, "output").map(fn(path) {
      resolve_config_path(base, path)
    }),
    payloads: payloads_field(fields, base),
    icons: string_array_field(fields, "icons").map(fn(path) {
      resolve_config_path(base, path)
    }),
    url_schemes: string_array_field(fields, "url_schemes"),
    document_types: document_types_field(fields),
    sign: bool_field(fields, "sign"),
    notarize: bool_field(fields, "notarize"),
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

///|
fn required(value : String?, name : String) -> String {
  match value {
    Some(value) => value
    None => abort("missing required option --" + name)
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
async fn run(args : ArrayView[String]) -> Unit {
  let matches = @argparse.parse(command(), argv=args, env=Map([])) catch {
    error => abort(error.to_string())
  }
  let config = match first(matches.values, "config") {
    Some(path) => read_config(path)
    None => empty_config()
  }
  let executable = prefer(
    first(matches.values, "executable"),
    config.executable,
  )
  let product_name = prefer(
    first(matches.values, "product-name"),
    config.product_name,
  )
  let identifier = prefer(
    first(matches.values, "identifier"),
    config.identifier,
  )
  let version = prefer(first(matches.values, "version"), config.version)
  let output = prefer(first(matches.values, "output"), config.output).unwrap_or(
    "dist",
  )
  let format_values = values(matches.values, "format")
  let formats = (if format_values.length() > 0 {
    format_values
  } else {
    config.formats
  }).map(value => @package.PackageFormat::parse(value))
  let icon_values = values(matches.values, "icon")
  let icons = if icon_values.length() > 0 { icon_values } else { config.icons }
  let scheme_values = values(matches.values, "url-scheme")
  let url_schemes = if scheme_values.length() > 0 {
    scheme_values
  } else {
    config.url_schemes
  }
  let spec = @package.PackageSpec::new(
    @path.Path(required(executable, "executable")).resolve().to_string(),
    required(product_name, "product-name"),
    required(identifier, "identifier"),
    required(version, "version"),
    formats,
    @path.Path(output).resolve().to_string(),
    payloads=config.payloads,
    icons=icons.map(fn(path) { @path.Path(path).resolve().to_string() }),
    url_schemes~,
    document_types=config.document_types,
    sign=matches.flags.get("sign").unwrap_or(false) || config.sign,
    notarize=matches.flags.get("notarize").unwrap_or(false) || config.notarize,
  )
  for artifact in @package.build(spec) {
    println(artifact)
  }
}

///|
async fn main {
  run(@env.args()[1:]) catch {
    error => {
      println("error: " + error.to_string())
      @sys.exit(1)
    }
  }
}
