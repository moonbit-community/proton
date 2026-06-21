///|
fn validate_non_empty(label : String, value : String) -> Result[Unit, String] {
  guard value.trim().to_owned() != "" else {
    return Err(label + " must not be empty")
  }
  Ok(())
}

///|
fn validate_identifier(label : String, value : String) -> Result[Unit, String] {
  match validate_non_empty(label, value) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  for i, ch in value {
    if i == 0 {
      guard is_identifier_start_char(ch) else {
        return Err(label + " must start with a lowercase letter or _")
      }
    } else {
      guard is_identifier_continue_char(ch) else {
        return Err(label + " must contain only identifier characters")
      }
    }
  }
  Ok(())
}

///|
fn validate_type_identifier(
  label : String,
  value : String,
) -> Result[Unit, String] {
  match validate_non_empty(label, value) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  for i, ch in value {
    if i == 0 {
      guard 'A' <= ch && ch <= 'Z' else {
        return Err(label + " must start with an uppercase letter")
      }
    } else {
      guard is_identifier_continue_char(ch) else {
        return Err(label + " must contain only identifier characters")
      }
    }
  }
  Ok(())
}

///|
fn validate_js_part(label : String, value : String) -> Result[Unit, String] {
  match validate_non_empty(label, value) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  guard value.find("/") is None else {
    return Err(label + " must not contain /")
  }
  guard value != "__proto__" && value != "prototype" && value != "constructor" else {
    return Err(label + " uses a reserved JavaScript property name")
  }
  Ok(())
}

///|
fn validate_extension_id(value : String) -> Result[Unit, String] {
  match validate_non_empty("extension id", value) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  guard value.find("\\") is None else {
    return Err("extension id must not contain \\")
  }
  guard value.find(" ") is None else {
    return Err("extension id must not contain spaces")
  }
  Ok(())
}

///|
fn validate_npm_package_name(package_name : String) -> Result[Unit, String] {
  guard package_name != "" else {
    return Err("moon.ext package must not be empty")
  }
  guard !package_name.contains("\\") &&
    (!package_name.contains("/") || package_name.has_prefix("@")) else {
    return Err(
      "moon.ext package must be an npm-style package name: " + package_name,
    )
  }
  guard !package_name.contains("..") &&
    !package_name.contains("://") &&
    !package_name.contains(" ") else {
    return Err("moon.ext package contains invalid characters: " + package_name)
  }
  if package_name.has_prefix("@") {
    let parts = package_name.split("/").collect()
    guard parts.length() == 2 else {
      return Err("moon.ext scoped package must be @scope/name: " + package_name)
    }
    validate_npm_package_part(parts[0][1:].to_owned(), package_name).bind(fn(
      _,
    ) {
      validate_npm_package_part(parts[1].to_owned(), package_name)
    })
  } else {
    validate_npm_package_part(package_name, package_name)
  }
}

///|
fn validate_npm_package_part(
  part : String,
  package_name : String,
) -> Result[Unit, String] {
  guard part != "" else {
    return Err("moon.ext package contains empty name segment: " + package_name)
  }
  for index, ch in part {
    if index == 0 {
      guard is_lowercase_ascii(ch) || is_digit_ascii(ch) else {
        return Err(
          "moon.ext package segment must start with lowercase letter or digit: " +
          package_name,
        )
      }
    }
    guard is_lowercase_ascii(ch) ||
      is_digit_ascii(ch) ||
      ch == '-' ||
      ch == '_' ||
      ch == '.' else {
      return Err("moon.ext package contains invalid character: " + package_name)
    }
  }
  Ok(())
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
