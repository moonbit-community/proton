///|
pub fn load_project_config_from_file(
  path : String,
) -> ProjectConfig raise ProjectConfigError {
  load_project_config_from_text(
    read_project_config_text(path),
    config_base_dir(path),
    name=path,
  )
}

///|
pub fn load_project_config_from_text(
  source : String,
  base_dir : String,
  name? : String = "proton.project.json",
) -> ProjectConfig raise ProjectConfigError {
  let json = @json.parse(source) catch {
    error => raise Syntax(name~, diagnostics=error.to_string())
  }
  load_project_config_from_json(json, base_dir)
}

///|
pub fn load_project_config_from_json(
  json : Json,
  base_dir : String,
) -> ProjectConfig raise ProjectConfigError {
  decode_project_config(json, base_dir)
}

///|
fn read_project_config_text(path : String) -> String raise ProjectConfigError {
  @mbfs.read_file_to_string(path, encoding="utf8") catch {
    error => raise FileRead(path~, detail=@debug.render(Repr(error)))
  }
}

///|
fn decode_project_config(
  json : Json,
  base_dir : String,
) -> ProjectConfig raise ProjectConfigError {
  guard json is Object(fields) else { raise InvalidRoot }
  validate_object_fields(fields, "proton.project.json", [
    "backend", "frontend", "package",
  ])
  let backend = decode_backend(fields, base_dir)
  let frontend = decode_frontend(fields, base_dir)
  let package_config = decode_package(fields, base_dir)
  ProjectConfig::new(base_dir, backend~, frontend~, package_config~)
}

///|
fn decode_backend(
  fields : Map[String, Json],
  base_dir : String,
) -> ProjectBackendConfig? raise ProjectConfigError {
  match fields.get("backend") {
    None => None
    Some(Object(values)) => {
      validate_object_fields(values, "backend", ["path", "package"])
      Some(
        ProjectBackendConfig::new(
          rebase_project_path(
            required_string(values, "path", "backend.path"),
            base_dir,
            "backend.path",
          ),
          required_string(values, "package", "backend.package"),
        ),
      )
    }
    Some(_) =>
      raise InvalidField(
        path="proton.project.json.backend",
        expectation="must be an object",
      )
  }
}

///|
fn decode_frontend(
  fields : Map[String, Json],
  base_dir : String,
) -> ProjectFrontendConfig? raise ProjectConfigError {
  match fields.get("frontend") {
    None => None
    Some(Object(values)) => {
      validate_object_fields(values, "frontend", [
        "path", "dev_url", "before_dev", "before_build", "dist",
      ])
      let path = optional_rebased_path(
        values, "path", "frontend.path", base_dir,
      )
      let frontend_root = path.unwrap_or(base_dir)
      Some(
        ProjectFrontendConfig::new(
          path~,
          dev_url=optional_string(values, "dev_url", "frontend.dev_url"),
          before_dev=optional_string(
            values, "before_dev", "frontend.before_dev",
          ),
          before_build=optional_string(
            values, "before_build", "frontend.before_build",
          ),
          dist=optional_rebased_path(
            values, "dist", "frontend.dist", frontend_root,
          ),
        ),
      )
    }
    Some(_) =>
      raise InvalidField(
        path="proton.project.json.frontend",
        expectation="must be an object",
      )
  }
}

///|
fn decode_package(
  fields : Map[String, Json],
  base_dir : String,
) -> ProjectPackageConfig? raise ProjectConfigError {
  match fields.get("package") {
    None => None
    Some(Object(values)) => {
      validate_object_fields(values, "package", [
        "product_name", "identifier", "version", "formats", "icons", "resources",
        "sign", "url_schemes", "document_types", "output",
      ])
      let formats = optional_string_array(values, "formats", "package.formats")
      validate_formats(formats)
      let icons = rebased_paths(
        optional_string_array(values, "icons", "package.icons"),
        base_dir,
        "package.icons",
      )
      let resources = rebased_paths(
        optional_string_array(values, "resources", "package.resources"),
        base_dir,
        "package.resources",
      )
      let url_schemes = optional_string_array(
        values, "url_schemes", "package.url_schemes",
      )
      validate_url_schemes(url_schemes)
      Some(
        ProjectPackageConfig::new(
          required_string(values, "product_name", "package.product_name"),
          required_string(values, "identifier", "package.identifier"),
          required_string(values, "version", "package.version"),
          formats~,
          icons~,
          resources~,
          url_schemes~,
          sign=decode_sign(values, base_dir),
          document_types=decode_document_types(values),
          output=rebase_project_path(
            optional_string(values, "output", "package.output").unwrap_or(
              "dist",
            ),
            base_dir,
            "package.output",
          ),
        ),
      )
    }
    Some(_) =>
      raise InvalidField(
        path="proton.project.json.package",
        expectation="must be an object",
      )
  }
}

///|
fn decode_sign(
  fields : Map[String, Json],
  base_dir : String,
) -> ProjectSignConfig? raise ProjectConfigError {
  match fields.get("sign") {
    None => None
    Some(Object(values)) => {
      validate_object_fields(values, "package.sign", ["binaries"])
      let binaries = optional_string_array(
        values, "binaries", "package.sign.binaries",
      )
      for path in binaries {
        if path.contains("*") {
          raise InvalidField(
            path="package.sign.binaries",
            expectation="must not contain glob patterns",
          )
        }
      }
      Some(
        ProjectSignConfig::new(
          binaries=rebased_paths(binaries, base_dir, "package.sign.binaries"),
        ),
      )
    }
    Some(_) =>
      raise InvalidField(path="package.sign", expectation="must be an object")
  }
}

///|
fn decode_document_types(
  fields : Map[String, Json],
) -> Array[ProjectDocumentType] raise ProjectConfigError {
  match fields.get("document_types") {
    None => []
    Some(Array(items)) => {
      let result : Array[ProjectDocumentType] = []
      for item in items {
        guard item is Object(values) else {
          raise InvalidField(
            path="package.document_types",
            expectation="must be an array of objects",
          )
        }
        validate_object_fields(values, "package.document_types", [
          "name", "extensions", "role",
        ])
        let extensions = optional_string_array(
          values, "extensions", "package.document_types.extensions",
        )
        guard extensions.length() > 0 else {
          raise MissingField(path="package.document_types.extensions")
        }
        result.push(
          ProjectDocumentType::new(
            required_string(values, "name", "package.document_types.name"),
            extensions,
            role=optional_string(values, "role", "package.document_types.role").unwrap_or(
              "Viewer",
            ),
          ),
        )
      }
      result
    }
    Some(_) =>
      raise InvalidField(
        path="package.document_types",
        expectation="must be an array",
      )
  }
}

///|
fn rebased_paths(
  paths : Array[String],
  base_dir : String,
  label : String,
) -> Array[String] raise ProjectConfigError {
  paths.map(path => rebase_project_path(path, base_dir, label))
}

///|
fn validate_formats(formats : Array[String]) -> Unit raise ProjectConfigError {
  validate_unique_values(formats, "package.formats", [
    "app", "zip", "dmg", "nsis", "appimage",
  ])
}

///|
fn validate_url_schemes(
  schemes : Array[String],
) -> Unit raise ProjectConfigError {
  let seen : Map[String, Unit] = Map([])
  for scheme in schemes {
    let normalized = scheme.to_lower()
    guard url_scheme_is_valid(normalized) else {
      raise UnsupportedValue(path="package.url_schemes", value=scheme)
    }
    guard !seen.contains(normalized) else {
      raise DuplicateValue(path="package.url_schemes", value=scheme)
    }
    seen[normalized] = ()
  }
}

///|
fn url_scheme_is_valid(scheme : String) -> Bool {
  guard scheme.length() > 0 else { return false }
  for index, ch in scheme {
    let letter = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
    if index == 0 {
      guard letter else { return false }
    } else {
      guard letter ||
        (ch >= '0' && ch <= '9') ||
        ch == '+' ||
        ch == '-' ||
        ch == '.' else {
        return false
      }
    }
  }
  true
}

///|
fn validate_unique_values(
  values : Array[String],
  label : String,
  allowed : Array[String],
) -> Unit raise ProjectConfigError {
  let seen : Map[String, Unit] = Map([])
  for value in values {
    guard allowed.contains(value) else {
      raise UnsupportedValue(path=label, value~)
    }
    guard !seen.contains(value) else {
      raise DuplicateValue(path=label, value~)
    }
    seen[value] = ()
  }
}

///|
fn validate_object_fields(
  fields : Map[String, Json],
  label : String,
  allowed : Array[String],
) -> Unit raise ProjectConfigError {
  let errors : Array[ProjectConfigError] = []
  for key, _ in fields {
    if !allowed.contains(key) {
      errors.push(UnknownField(path=label + "." + key))
    }
  }
  raise_errors(errors)
}

///|
fn raise_errors(
  errors : Array[ProjectConfigError],
) -> Unit raise ProjectConfigError {
  if errors.length() == 1 {
    raise errors[0]
  }
  if errors.length() > 1 {
    raise Validation(errors~)
  }
}

///|
fn required_string(
  fields : Map[String, Json],
  key : String,
  label : String,
) -> String raise ProjectConfigError {
  match optional_string(fields, key, label) {
    Some(value) => value
    None => raise MissingField(path=label)
  }
}

///|
fn optional_string(
  fields : Map[String, Json],
  key : String,
  label : String,
) -> String? raise ProjectConfigError {
  match fields.get(key) {
    None => None
    Some(String(value)) if value.trim().to_owned() != "" => Some(value)
    Some(String(_)) =>
      raise InvalidField(path=label, expectation="must not be empty")
    Some(_) => raise InvalidField(path=label, expectation="must be a string")
  }
}

///|
fn optional_rebased_path(
  fields : Map[String, Json],
  key : String,
  label : String,
  base_dir : String,
) -> String? raise ProjectConfigError {
  optional_string(fields, key, label).map(path => {
    rebase_project_path(path, base_dir, label)
  })
}

///|
fn optional_string_array(
  fields : Map[String, Json],
  key : String,
  label : String,
) -> Array[String] raise ProjectConfigError {
  match fields.get(key) {
    None => []
    Some(Array(items)) =>
      items.map(item => {
        guard item is String(value) && value.trim().to_owned() != "" else {
          raise InvalidField(
            path=label,
            expectation="must be an array of non-empty strings",
          )
        }
        value
      })
    Some(_) =>
      raise InvalidField(path=label, expectation="must be an array of strings")
  }
}
