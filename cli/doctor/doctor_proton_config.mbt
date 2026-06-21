///|
fn read_proton_project_config(path : String) -> Result[DoctorAppConfig, String] {
  try @mbfs.read_file_to_string(path, encoding="utf8") catch {
    err =>
      Err("failed to read moon.proton: " + @debug.render(@debug.to_repr(err)))
  } noraise {
    text => {
      let (ast, reports) = @proton_config.parse_moon_proton(name=path, text)
      if reports.length() > 0 {
        return Err(render_proton_config_reports(reports))
      }
      match ast {
        Obj(fields, _) => decode_doctor_app_config(fields)
        _ => Err("moon.proton root must be a field list")
      }
    }
  }
}

///|
fn decode_doctor_app_config(
  fields : Array[@proton_config.ConfigField],
) -> Result[DoctorAppConfig, String] {
  validate_proton_top_level_fields(fields).bind(fn(_) {
    required_object_field(fields, "window", "moon.proton window").bind(fn(
      window_fields,
    ) {
      required_object_field(fields, "entry", "moon.proton entry").bind(fn(
        entry_fields,
      ) {
        decode_doctor_window(window_fields).bind(fn(window) {
          decode_doctor_entry(entry_fields).bind(fn(entry) {
            optional_bool_config_field(fields, "debug", false).bind(fn(debug) {
              optional_doctor_frontend(fields).map(fn(frontend) {
                DoctorAppConfig::{ window, entry, debug, frontend }
              })
            })
          })
        })
      })
    })
  })
}

///|
fn decode_doctor_window(
  fields : Array[@proton_config.ConfigField],
) -> Result[DoctorAppWindow, String] {
  validate_object_fields(fields, "window", [
    "title", "width", "height", "size_hint",
  ]).bind(fn(_) {
    required_string_config_field(fields, "title", "window.title").bind(fn(
      title,
    ) {
      required_positive_int_config_field(fields, "width", "window.width").bind(fn(
        width,
      ) {
        required_positive_int_config_field(fields, "height", "window.height").bind(fn(
            height,
          ) {
            optional_string_config_field(
              fields, "size_hint", "window.size_hint",
            ).bind(fn(size_hint) {
              parse_doctor_size_hint(size_hint).map(fn(size_hint) {
                DoctorAppWindow::{ title, width, height, size_hint }
              })
            })
          },
        )
      })
    })
  })
}

///|
fn decode_doctor_entry(
  fields : Array[@proton_config.ConfigField],
) -> Result[DoctorAppEntry, String] {
  validate_object_fields(fields, "entry", ["kind", "value"]).bind(fn(_) {
    required_string_config_field(fields, "kind", "entry.kind").bind(fn(kind) {
      required_string_config_field(fields, "value", "entry.value").bind(fn(
        value,
      ) {
        validate_doctor_entry_kind(kind).map(fn(_) {
          DoctorAppEntry::{ kind, value }
        })
      })
    })
  })
}

///|
fn optional_doctor_frontend(
  fields : Array[@proton_config.ConfigField],
) -> Result[DoctorFrontendConfig?, String] {
  match find_config_field(fields, "frontend") {
    None => Ok(None)
    Some(Obj(frontend_fields, _)) =>
      validate_object_fields(frontend_fields, "frontend", [
        "dev_url", "dist", "before_dev", "before_build",
      ]).bind(fn(_) {
        optional_string_config_field(
          frontend_fields, "before_build", "frontend.before_build",
        ).bind(fn(before_build) {
          optional_string_config_field(frontend_fields, "dist", "frontend.dist").bind(fn(
              dist,
            ) {
              optional_string_config_field(
                frontend_fields, "dev_url", "frontend.dev_url",
              ).map(fn(dev_url) {
                Some(DoctorFrontendConfig::{ before_build, dist, dev_url })
              })
            },
          )
        })
      })
    Some(_) => Err("moon.proton field `frontend` must be an object")
  }
}

///|
fn validate_proton_top_level_fields(
  fields : Array[@proton_config.ConfigField],
) -> Result[Unit, String] {
  let seen : Map[String, Unit] = {}
  for field in fields {
    if seen.contains(field.key) {
      return Err("duplicate moon.proton field: " + field.key)
    }
    seen[field.key] = ()
    match field.key {
      "window"
      | "entry"
      | "debug"
      | "product_name"
      | "identifier"
      | "frontend"
      | "bundle" => ()
      "extensions" =>
        return Err(
          "moon.proton field `extensions` is not supported; declare extensions in MoonBit code with .extension(...)",
        )
      "permissions" =>
        return Err("moon.proton field `permissions` is not supported in v1")
      "windows" =>
        return Err("moon.proton field `windows` is not supported in v1")
      other => return Err("unknown moon.proton field: " + other)
    }
  }
  Ok(())
}

///|
fn validate_object_fields(
  fields : Array[@proton_config.ConfigField],
  label : String,
  allowed : Array[String],
) -> Result[Unit, String] {
  let seen : Map[String, Unit] = {}
  for field in fields {
    if seen.contains(field.key) {
      return Err("duplicate " + label + " field: " + field.key)
    }
    seen[field.key] = ()
    if !allowed.contains(field.key) {
      return Err("unknown " + label + " field: " + field.key)
    }
  }
  Ok(())
}

///|
fn required_object_field(
  fields : Array[@proton_config.ConfigField],
  key : String,
  label : String,
) -> Result[Array[@proton_config.ConfigField], String] {
  match find_config_field(fields, key) {
    Some(Obj(fields, _)) => Ok(fields)
    Some(_) => Err(label + " must be an object")
    None => Err("missing required moon.proton field: " + key)
  }
}

///|
fn required_string_config_field(
  fields : Array[@proton_config.ConfigField],
  key : String,
  label : String,
) -> Result[String, String] {
  match find_config_field(fields, key) {
    Some(Str(value, _)) =>
      if value == "" {
        Err(label + " must not be empty")
      } else {
        Ok(value)
      }
    Some(_) => Err(label + " must be a string")
    None => Err("missing required field: " + label)
  }
}

///|
fn optional_string_config_field(
  fields : Array[@proton_config.ConfigField],
  key : String,
  label : String,
) -> Result[String?, String] {
  match find_config_field(fields, key) {
    None => Ok(None)
    Some(Str(value, _)) =>
      if value == "" {
        Err(label + " must not be empty")
      } else {
        Ok(Some(value))
      }
    Some(_) => Err(label + " must be a string")
  }
}

///|
fn optional_bool_config_field(
  fields : Array[@proton_config.ConfigField],
  key : String,
  default : Bool,
) -> Result[Bool, String] {
  match find_config_field(fields, key) {
    None => Ok(default)
    Some(Bool(value, _)) => Ok(value)
    Some(_) => Err("moon.proton " + key + " must be a bool")
  }
}

///|
fn required_positive_int_config_field(
  fields : Array[@proton_config.ConfigField],
  key : String,
  label : String,
) -> Result[Int, String] {
  match find_config_field(fields, key) {
    Some(Int(text, _)) =>
      try @string.parse_int(text) catch {
        _ => Err(label + " must be an int")
      } noraise {
        value =>
          if value <= 0 {
            Err(label + " must be positive")
          } else {
            Ok(value)
          }
      }
    Some(_) => Err(label + " must be an int")
    None => Err("missing required field: " + label)
  }
}

///|
fn parse_doctor_size_hint(value : String?) -> Result[String, String] {
  match value {
    None => Ok("none")
    Some("none") => Ok("none")
    Some("fixed") => Ok("fixed")
    Some("min") => Ok("min")
    Some("max") => Ok("max")
    Some(other) => Err("unsupported window.size_hint: " + other)
  }
}

///|
fn validate_doctor_entry_kind(kind : String) -> Result[Unit, String] {
  match kind {
    "html" | "url" | "file" | "asset" => Ok(())
    _ => Err("unsupported app entry kind: " + kind)
  }
}

///|
fn find_config_field(
  fields : Array[@proton_config.ConfigField],
  key : String,
) -> @proton_config.Ast? {
  for field in fields {
    if field.key == key {
      return Some(field.value)
    }
  }
  None
}

///|
fn render_proton_config_reports(reports : Array[@lexer_basic.Report]) -> String {
  let builder = StringBuilder::new()
  for index, report in reports {
    if index > 0 {
      builder.write_string("\n")
    }
    builder.write_string(report.to_string())
  }
  builder.to_string()
}
