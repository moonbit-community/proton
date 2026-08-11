///|
/// Returns a normalized JSON summary suitable for `proton inspect config`.
pub fn ProtonProjectConfig::to_summary_json(self : ProtonProjectConfig) -> Json {
  let loaded = self.manifest()
  let manifest = loaded.manifest()
  {
    "runtime": {
      "base_dir": optional_string_json(loaded.base_dir()),
      "window": window_summary_json(manifest.window),
      "entry": entry_summary_json(manifest.entry),
      "windows": manifest.windows.map(fn(window) -> Json {
        {
          "id": window.id,
          "window": window_summary_json(window.window),
          "entry": entry_summary_json(window.entry),
        }
      }),
      "dev_entry": entry_summary_json(self.dev_manifest().manifest().entry),
      "debug": manifest.debug != 0,
      "single_instance": self.single_instance(),
    },
    "metadata": metadata_summary_json(self.metadata()),
    "backend": backend_summary_json(self.backend()),
    "frontend": frontend_summary_json(self.frontend()),
    "bundle": bundle_summary_json(self.bundle()),
  }
}

///|
fn metadata_summary_json(metadata : ProtonAppMetadata) -> Json {
  {
    "product_name": metadata.product_name(),
    "identifier": optional_string_json(metadata.identifier()),
    "version": optional_string_json(metadata.version()),
    "description": optional_string_json(metadata.description()),
    "license": optional_string_json(metadata.license()),
  }
}

///|
fn backend_summary_json(backend : ProtonBackendConfig?) -> Json {
  match backend {
    None => null
    Some(backend) =>
      { "path": backend.path(), "package": backend.app_package() }
  }
}

///|
fn frontend_summary_json(frontend : ProtonFrontendConfig?) -> Json {
  match frontend {
    None => null
    Some(frontend) =>
      {
        "dev_url": optional_string_json(frontend.dev_url()),
        "dist": optional_string_json(frontend.dist()),
        "before_dev": optional_string_json(frontend.before_dev()),
        "before_build": optional_string_json(frontend.before_build()),
        "path": optional_string_json(frontend.path()),
      }
  }
}

///|
fn bundle_summary_json(bundle : ProtonBundleConfig?) -> Json {
  match bundle {
    None => null
    Some(bundle) =>
      {
        "active": bundle.active(),
        "targets": string_array_json(bundle.targets()),
        "icon": string_array_json(bundle.icon()),
        "resources": string_array_json(bundle.resources()),
        "sign": match bundle.sign() {
          Some(sign) => { "binaries": string_array_json(sign.binaries()) }
          None => null
        },
        "url_schemes": string_array_json(bundle.url_schemes()),
        "document_types": bundle
        .document_types()
        .map(fn(document_type) -> Json {
          {
            "name": document_type.name,
            "extensions": string_array_json(document_type.extensions),
            "role": document_type.role,
          }
        }),
        "output": bundle.output(),
      }
  }
}

///|
fn window_summary_json(window : @manifest.WindowManifest) -> Json {
  {
    "title": window.title,
    "width": window.width,
    "height": window.height,
    "size_hint": size_hint_summary_text(window.size_hint),
    "titlebar_style": titlebar_style_summary_text(window.titlebar_style),
  }
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
  { "kind": kind, "value": value }
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
    Some(value) => Json(value)
    None => null
  }
}

///|
fn string_array_json(values : Array[String]) -> Json {
  Json(values)
}
