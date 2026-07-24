///|
/// Converts the optional textual `size_hint` into the manifest enum value.
fn parse_size_hint(
  size_hint : String?,
) -> @manifest.WindowSizeHint raise BootstrapError {
  match size_hint {
    None => @manifest.WindowSizeHint::None
    Some(size_hint) =>
      match normalize_keyword(size_hint) {
        "none" => @manifest.WindowSizeHint::None
        "min" => @manifest.WindowSizeHint::Min
        "max" => @manifest.WindowSizeHint::Max
        "fixed" => @manifest.WindowSizeHint::Fixed
        _ => raise UnsupportedValue(path="window.size_hint", value=size_hint)
      }
  }
}

///|
fn parse_titlebar_style(
  titlebar_style : String?,
) -> @manifest.TitlebarStyle raise BootstrapError {
  match titlebar_style {
    None => @manifest.TitlebarStyle::Default
    Some(titlebar_style) =>
      match normalize_keyword(titlebar_style) {
        "default" => @manifest.TitlebarStyle::Default
        "overlay" => @manifest.TitlebarStyle::Overlay
        _ =>
          raise UnsupportedValue(
            path="window.titlebar_style",
            value=titlebar_style,
          )
      }
  }
}

///|
/// Resolves a relative config path against the config file base directory.
fn rebase_relative_path(path : String, base_dir : String?) -> String {
  match base_dir {
    None => path
    Some(base_dir) => {
      let candidate : @mbpath.Path = path
      if candidate.is_absolute() {
        path
      } else {
        let base : @mbpath.Path = base_dir
        base.join(path).normalize().to_string()
      }
    }
  }
}

///|
/// Trims and lowercases config keywords before comparison.
fn normalize_keyword(raw : String) -> String {
  raw.trim().to_owned().to_lower()
}

///|
/// Returns the optional integer or a fallback default.
fn int_or_default(value : Int?, fallback : Int) -> Int {
  match value {
    Some(value) => value
    None => fallback
  }
}
