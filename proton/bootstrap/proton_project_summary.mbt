///|
/// Returns a normalized JSON summary suitable for `proton inspect config`.
pub fn ProtonProjectConfig::to_summary_json(self : ProtonProjectConfig) -> Json {
  let loaded = self.manifest()
  let manifest = loaded.manifest()
  Json::object({
    "runtime": Json::object({
      "base_dir": optional_string_json(loaded.base_dir()),
      "window": window_summary_json(manifest.window),
      "entry": entry_summary_json(manifest.entry),
      "dev_entry": entry_summary_json(self.dev_manifest().manifest().entry),
      "debug": Json::boolean(manifest.debug != 0),
    }),
    "metadata": metadata_summary_json(self.metadata()),
    "frontend": frontend_summary_json(self.frontend()),
    "bundle": bundle_summary_json(self.bundle()),
  })
}

///|
fn metadata_summary_json(metadata : ProtonAppMetadata) -> Json {
  Json::object({
    "product_name": Json::string(metadata.product_name()),
    "identifier": optional_string_json(metadata.identifier()),
    "version": optional_string_json(metadata.version()),
    "description": optional_string_json(metadata.description()),
    "license": optional_string_json(metadata.license()),
  })
}

///|
fn frontend_summary_json(frontend : ProtonFrontendConfig?) -> Json {
  match frontend {
    None => Json::null()
    Some(frontend) =>
      Json::object({
        "dev_url": optional_string_json(frontend.dev_url()),
        "dist": optional_string_json(frontend.dist()),
        "before_dev": optional_string_json(frontend.before_dev()),
        "before_build": optional_string_json(frontend.before_build()),
        "cwd": optional_string_json(frontend.cwd()),
      })
  }
}

///|
fn bundle_summary_json(bundle : ProtonBundleConfig?) -> Json {
  match bundle {
    None => Json::null()
    Some(bundle) =>
      Json::object({
        "active": Json::boolean(bundle.active()),
        "targets": string_array_json(bundle.targets()),
        "icon": string_array_json(bundle.icon()),
        "resources": string_array_json(bundle.resources()),
        "output": Json::string(bundle.output()),
      })
  }
}

///|
fn window_summary_json(window : @manifest.WindowManifest) -> Json {
  Json::object({
    "title": Json::string(window.title),
    "width": ToJson::to_json(window.width),
    "height": ToJson::to_json(window.height),
    "size_hint": Json::string(size_hint_summary_text(window.size_hint)),
    "titlebar_style": Json::string(
      titlebar_style_summary_text(window.titlebar_style),
    ),
  })
}

///|
fn entry_summary_json(entry : @manifest.AppEntry) -> Json {
  match entry {
    Html(value) => entry_summary_object("html", value)
    Url(value) => entry_summary_object("url", value)
    File(value) => entry_summary_object("file", value)
    Asset(value) => entry_summary_object("asset", value)
  }
}

///|
fn entry_summary_object(kind : String, value : String) -> Json {
  Json::object({ "kind": Json::string(kind), "value": Json::string(value) })
}

///|
fn size_hint_summary_text(size_hint : @manifest.WindowSizeHint) -> String {
  match size_hint {
    None => "none"
    Fixed => "fixed"
    Min => "min"
    Max => "max"
  }
}

///|
fn titlebar_style_summary_text(
  titlebar_style : @manifest.TitlebarStyle,
) -> String {
  match titlebar_style {
    Default => "default"
    Overlay => "overlay"
  }
}

///|
fn optional_string_json(value : String?) -> Json {
  match value {
    Some(value) => Json::string(value)
    None => Json::null()
  }
}

///|
fn string_array_json(values : Array[String]) -> Json {
  Json::array(values.map(fn(value) { Json::string(value) }))
}
