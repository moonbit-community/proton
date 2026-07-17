///|
fn config_path() -> String {
  if @mbfs.path_exists("44_project_config/moon.proton") {
    "44_project_config/moon.proton"
  } else {
    "examples/44_project_config/moon.proton"
  }
}

///|
fn[T] require_some(value : T?, label : String) -> T {
  match value {
    Some(value) => value
    None => abort("missing " + label)
  }
}

///|
fn assert_string(value : String, expected : String, label : String) -> Unit {
  guard value == expected else {
    abort(label + ": expected `" + expected + "`, got `" + value + "`")
  }
}

///|
fn assert_path_suffix(value : String, suffix : String, label : String) -> Unit {
  let normalized = value.replace_all(old="\\", new="/")
  guard normalized.has_suffix(suffix) else {
    abort(label + ": expected suffix `" + suffix + "`, got `" + value + "`")
  }
}

///|
fn assert_bool(value : Bool, expected : Bool, label : String) -> Unit {
  guard value == expected else {
    abort(label + " did not match expected value")
  }
}

///|
fn assert_strings(
  value : Array[String],
  expected : Array[String],
  label : String,
) -> Unit {
  guard value == expected else {
    abort(label + " did not match expected values")
  }
}

///|
fn main {
  let config = match
    @bootstrap.load_proton_project_config_from_file(config_path()) {
    Ok(config) => config
    Err(error) => abort(error)
  }
  let manifest = config.manifest().manifest()
  assert_string(manifest.window.title, "Proton Project Config", "window.title")
  assert_bool(manifest.debug == 1, true, "debug")

  let metadata = config.metadata()
  assert_string(
    metadata.product_name(),
    "Proton Project Config",
    "product_name",
  )
  assert_string(
    require_some(metadata.identifier(), "identifier"),
    "com.justjavac.proton.project-config",
    "identifier",
  )
  assert_string(require_some(metadata.version(), "version"), "0.1.0", "version")

  let frontend = require_some(config.frontend(), "frontend")
  assert_string(
    require_some(frontend.dev_url(), "frontend.dev_url"),
    "http://localhost:5173",
    "frontend.dev_url",
  )
  assert_path_suffix(
    require_some(frontend.dist(), "frontend.dist"),
    "44_project_config/frontend/dist",
    "frontend.dist",
  )

  let bundle = require_some(config.bundle(), "bundle")
  assert_bool(bundle.active(), true, "bundle.active")
  assert_strings(bundle.targets(), ["app", "zip"], "bundle.targets")
  assert_path_suffix(
    bundle.output(),
    "44_project_config/target/proton-dist",
    "bundle.output",
  )

  match config.dev_manifest().manifest().entry {
    @manifest.AppEntry::Url(url) =>
      assert_string(url, "http://localhost:5173", "dev entry")
    _ => abort("expected dev manifest to use frontend.dev_url")
  }
}
