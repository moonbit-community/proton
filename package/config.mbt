///|
priv struct ConfigPayload {
  source : String
  destination : String
  location : String?
} derive(FromJson)

///|
priv struct ConfigDocumentType {
  name : String
  extensions : Array[String]
  role : String?
} derive(FromJson)

///|
priv struct PackageConfig {
  schema_version : Int
  executable : String?
  product_name : String?
  identifier : String?
  version : String?
  formats : Array[String]?
  output : String?
  payloads : Array[ConfigPayload]?
  icons : Array[String]?
  url_schemes : Array[String]?
  document_types : Array[ConfigDocumentType]?
  nsis_install_mode : String?
  sign : Bool?
  notarize : Bool?
} derive(FromJson, Default)

///|
priv suberror PackageCommandError {
  InvalidConfig(path~ : String, detail~ : String)
  UnsupportedSchema(version~ : Int)
  MissingOption(name~ : String)
} derive(Debug)

///|
impl Show for PackageCommandError with fn output(self, logger) {
  logger.write_string(
    match self {
      InvalidConfig(path~, detail~) =>
        "invalid package config " + path + ": " + detail
      UnsupportedSchema(version~) =>
        "unsupported package config schema version " + version.to_string()
      MissingOption(name~) => "missing required option --" + name
    },
  )
}

///|
fn decode_package_config(
  source : String,
  path : String,
) -> PackageConfig raise PackageCommandError {
  let config : PackageConfig = @json.from_json(@json.parse(source)) catch {
    error =>
      raise PackageCommandError::InvalidConfig(path~, detail=error.to_string())
  }
  guard config.schema_version == 1 else {
    raise PackageCommandError::UnsupportedSchema(version=config.schema_version)
  }
  config
}

///|
async fn load_package_config(path : String) -> (PackageConfig, String) {
  let absolute = @path.Path(path).resolve()
  let source = @async_fs.read_file(absolute.to_string()).text() catch {
    error =>
      raise PackageCommandError::InvalidConfig(
        path=absolute.to_string(),
        detail=error.to_string(),
      )
  }
  (
    decode_package_config(source, absolute.to_string()),
    absolute.dirname().to_string(),
  )
}

///|
fn PackageConfig::payload_specs(
  self : PackageConfig,
  base : String,
) -> Array[@package.Payload] raise @package.PackagePlanError {
  self.payloads
  .unwrap_or([])
  .map(payload => {
    let location = match payload.location {
      Some(value) => @package.PayloadLocation::parse(value)
      None => @package.PayloadLocation::Resources
    }
    @package.Payload(
      resolve_path(base, payload.source),
      payload.destination,
      location~,
    )
  })
}

///|
fn PackageConfig::document_type_specs(
  self : PackageConfig,
) -> Array[@package.DocumentType] {
  self.document_types
  .unwrap_or([])
  .map(document_type => {
    @package.DocumentType(
      document_type.name,
      document_type.extensions,
      role=document_type.role.unwrap_or("Viewer"),
    )
  })
}

///|
fn resolve_path(base : String, value : String) -> String {
  let path : @path.Path = value
  if path.is_absolute() {
    path.resolve().to_string()
  } else {
    @path.Path(base).join(path).resolve().to_string()
  }
}
