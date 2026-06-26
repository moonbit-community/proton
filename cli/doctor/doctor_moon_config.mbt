///|
fn report_messages(reports : Array[@lexer_basic.Report]) -> String {
  if reports.length() == 0 {
    ""
  } else {
    reports.map(fn(report) { report.to_string() }).join("; ")
  }
}

///|
fn ast_field(ast : @moon_config.Ast, key : String) -> @moon_config.Ast? {
  match ast {
    @moon_config.Ast::Obj(fields, ..) => {
      for field in fields {
        let (field_key, value) = field
        if field_key == key {
          return Some(value)
        }
      }
      None
    }
    _ => None
  }
}

///|
fn ast_string(ast : @moon_config.Ast?) -> String? {
  match ast {
    Some(@moon_config.Ast::Str(value, ..)) => Some(value)
    _ => None
  }
}

///|
fn ast_bool(ast : @moon_config.Ast?) -> Bool? {
  match ast {
    Some(@moon_config.Ast::Bool(value, ..)) => Some(value)
    _ => None
  }
}

///|
fn read_moon_file(path : String) -> Result[String, MoonConfigReadError] {
  if !@mbfs.path_exists(path) {
    Err(MoonConfigReadError::MissingFile(path))
  } else {
    try @mbfs.read_file_to_string(path, encoding="utf8") catch {
      err =>
        Err(
          MoonConfigReadError::ReadFailed(
            path,
            @debug.render(@debug.to_repr(err)),
          ),
        )
    } noraise {
      text => Ok(text)
    }
  }
}

///|
fn parse_deps(ast : @moon_config.Ast) -> Array[MoonDependency] {
  match ast_field(ast, "deps") {
    Some(@moon_config.Ast::Obj(fields, ..)) => {
      let deps : Array[MoonDependency] = []
      for field in fields {
        let (module_name, version_ast) = field
        let version = match version_ast {
          @moon_config.Ast::Str("", ..) => None
          @moon_config.Ast::Str(value, ..) => Some(value)
          _ => None
        }
        deps.push({ module_name, version })
      }
      deps
    }
    _ => []
  }
}

///|
fn parse_pkg_imports(ast : @moon_config.Ast) -> Array[MoonPackageImport] {
  match ast_field(ast, "import") {
    Some(@moon_config.Ast::Obj(fields, ..)) => {
      let imports : Array[MoonPackageImport] = []
      for field in fields {
        let (package_path, alias_ast) = field
        let package_alias = match alias_ast {
          @moon_config.Ast::Str("", ..) => None
          @moon_config.Ast::Str(value, ..) => Some(value)
          _ => None
        }
        imports.push({ package_path, package_alias })
      }
      imports
    }
    Some(@moon_config.Ast::Arr(items, ..)) => {
      let imports : Array[MoonPackageImport] = []
      for item in items {
        match item {
          @moon_config.Ast::Str(package_path, ..) =>
            imports.push({ package_path, package_alias: None })
          @moon_config.Ast::Obj(fields, ..) => {
            let mut package_path : String? = None
            let mut package_alias : String? = None
            for field in fields {
              let (key, value) = field
              match (key, value) {
                ("path", @moon_config.Ast::Str(value, ..)) =>
                  package_path = Some(value)
                ("alias", @moon_config.Ast::Str(value, ..)) =>
                  package_alias = Some(value)
                _ => ()
              }
            }
            match package_path {
              Some(package_path) =>
                imports.push({ package_path, package_alias })
              None => ()
            }
          }
          _ => ()
        }
      }
      imports
    }
    _ => []
  }
}

///|
fn read_moon_mod(
  path : String,
) -> Result[MoonModuleConfig, MoonConfigReadError] {
  match read_moon_file(path) {
    Err(err) => Err(err)
    Ok(source) => {
      let (ast, reports) = @moon_config.parse_moon_mod(name=path, source)
      if reports.length() > 0 {
        Err(MoonConfigReadError::ParseFailed(path, report_messages(reports)))
      } else {
        Ok({
          path,
          name: ast_string(ast_field(ast, "name")),
          version: ast_string(ast_field(ast, "version")),
          imports: parse_deps(ast),
        })
      }
    }
  }
}

///|
fn read_moon_pkg(
  path : String,
) -> Result[MoonPackageConfig, MoonConfigReadError] {
  match read_moon_file(path) {
    Err(err) => Err(err)
    Ok(source) => {
      let (ast, reports) = @moon_config.parse_moon_pkg(name=path, source)
      if reports.length() > 0 {
        Err(MoonConfigReadError::ParseFailed(path, report_messages(reports)))
      } else {
        Ok({
          path,
          imports: parse_pkg_imports(ast),
          is_main: ast_bool(ast_field(ast, "is-main")),
        })
      }
    }
  }
}
