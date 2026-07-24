///|
fn validate_non_empty(label : String, value : String) -> Unit raise {
  guard value.trim().to_owned() != "" else {
    raise CommandCodegenError::InvalidName(
      label~,
      value~,
      reason="must not be empty",
    )
  }
}

///|
fn validate_identifier(label : String, value : String) -> Unit raise {
  validate_non_empty(label, value)
  for i, ch in value {
    if i == 0 {
      guard is_identifier_start_char(ch) else {
        raise CommandCodegenError::InvalidName(
          label~,
          value~,
          reason="must start with a lowercase letter or _",
        )
      }
    } else {
      guard is_identifier_continue_char(ch) else {
        raise CommandCodegenError::InvalidName(
          label~,
          value~,
          reason="must contain only identifier characters",
        )
      }
    }
  }
}

///|
fn validate_type_identifier(label : String, value : String) -> Unit raise {
  validate_non_empty(label, value)
  for i, ch in value {
    if i == 0 {
      guard 'A' <= ch && ch <= 'Z' else {
        raise CommandCodegenError::InvalidName(
          label~,
          value~,
          reason="must start with an uppercase letter",
        )
      }
    } else {
      guard is_identifier_continue_char(ch) else {
        raise CommandCodegenError::InvalidName(
          label~,
          value~,
          reason="must contain only identifier characters",
        )
      }
    }
  }
}

///|
fn validate_js_part(label : String, value : String) -> Unit raise {
  validate_non_empty(label, value)
  guard value.find("/") is None else {
    raise CommandCodegenError::InvalidName(
      label~,
      value~,
      reason="must not contain /",
    )
  }
  guard value != "__proto__" && value != "prototype" && value != "constructor" else {
    raise CommandCodegenError::InvalidName(
      label~,
      value~,
      reason="uses a reserved JavaScript property name",
    )
  }
}

///|
fn validate_extension_id(value : String) -> Unit raise {
  validate_non_empty("extension id", value)
  guard value.find("\\") is None else {
    raise CommandCodegenError::InvalidName(
      label="extension id",
      value~,
      reason="must not contain \\",
    )
  }
  guard value.find(" ") is None else {
    raise CommandCodegenError::InvalidName(
      label="extension id",
      value~,
      reason="must not contain spaces",
    )
  }
}

///|
fn validate_npm_package_name(
  package_name : String,
) -> Unit raise CodegenMetadataError {
  guard package_name != "" else {
    raise InvalidPackageName(value=package_name, reason="must not be empty")
  }
  guard !package_name.contains("\\") &&
    (!package_name.contains("/") || package_name.has_prefix("@")) else {
    raise InvalidPackageName(
      value=package_name,
      reason="must be an npm-style package name",
    )
  }
  guard !package_name.contains("..") &&
    !package_name.contains("://") &&
    !package_name.contains(" ") else {
    raise InvalidPackageName(
      value=package_name,
      reason="contains invalid characters",
    )
  }
  if package_name.has_prefix("@") {
    let parts = package_name.split("/").collect()
    guard parts.length() == 2 else {
      raise InvalidPackageName(
        value=package_name,
        reason="scoped packages must use @scope/name",
      )
    }
    validate_npm_package_part(parts[0][1:].to_owned(), package_name)
    validate_npm_package_part(parts[1].to_owned(), package_name)
  } else {
    validate_npm_package_part(package_name, package_name)
  }
}

///|
fn validate_npm_package_part(
  part : String,
  package_name : String,
) -> Unit raise CodegenMetadataError {
  guard part != "" else {
    raise InvalidPackageName(
      value=package_name,
      reason="contains an empty name segment",
    )
  }
  for index, ch in part {
    if index == 0 {
      guard is_lowercase_ascii(ch) || is_digit_ascii(ch) else {
        raise InvalidPackageName(
          value=package_name,
          reason="segments must start with a lowercase letter or digit",
        )
      }
    }
    guard is_lowercase_ascii(ch) ||
      is_digit_ascii(ch) ||
      ch == '-' ||
      ch == '_' ||
      ch == '.' else {
      raise InvalidPackageName(
        value=package_name,
        reason="contains an invalid character",
      )
    }
  }
}

///|
fn is_identifier_start_char(ch : Char) -> Bool {
  ('a' <= ch && ch <= 'z') || ch == '_'
}

///|
fn is_identifier_continue_char(ch : Char) -> Bool {
  is_identifier_start_char(ch) ||
  ('A' <= ch && ch <= 'Z') ||
  ('0' <= ch && ch <= '9')
}

///|
fn is_lowercase_ascii(ch : Char) -> Bool {
  'a' <= ch && ch <= 'z'
}

///|
fn is_digit_ascii(ch : Char) -> Bool {
  '0' <= ch && ch <= '9'
}

///|
fn lower_camel_from_snake(name : String) -> String {
  let builder = StringBuilder::new()
  let mut upper_next = false
  for _, ch in name {
    if ch == '_' {
      upper_next = true
    } else if upper_next {
      builder.write_string(char_to_upper_string(ch))
      upper_next = false
    } else {
      builder.write_char(ch)
    }
  }
  builder.to_string()
}

///|
fn lower_camel_from_pascal(name : String) -> String {
  let builder = StringBuilder::new()
  for i, ch in name {
    if i == 0 {
      builder.write_string(char_to_lower_string(ch))
    } else {
      builder.write_char(ch)
    }
  }
  builder.to_string()
}

///|
fn pascal_from_snake(name : String) -> String {
  let builder = StringBuilder::new()
  let mut upper_next = true
  for _, ch in name {
    if ch == '_' {
      upper_next = true
    } else if upper_next {
      builder.write_string(char_to_upper_string(ch))
      upper_next = false
    } else {
      builder.write_char(ch)
    }
  }
  builder.to_string()
}

///|
fn snake_from_camel(name : String) -> String {
  let builder = StringBuilder::new()
  for i, ch in name {
    if 'A' <= ch && ch <= 'Z' {
      if i > 0 {
        builder.write_char('_')
      }
      builder.write_string(char_to_lower_string(ch))
    } else {
      builder.write_char(ch)
    }
  }
  builder.to_string()
}

///|
fn char_to_upper_string(ch : Char) -> String {
  let s = String::make(1, ch)
  s.to_upper()
}

///|
fn char_to_lower_string(ch : Char) -> String {
  let s = String::make(1, ch)
  s.to_lower()
}
