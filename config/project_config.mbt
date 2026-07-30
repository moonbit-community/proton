///|
pub(all) enum ProjectWindowSizeHint {
  WindowSizeNone
  WindowSizeMin
  WindowSizeMax
  WindowSizeFixed
} derive(Eq, Debug)

///|
pub(all) enum ProjectTitlebarStyle {
  TitlebarDefault
  TitlebarOverlay
} derive(Eq, Debug)

///|
pub(all) enum ProjectEntry {
  Html(String)
  Url(String)
  File(String)
  Asset(String)
} derive(Eq, Debug)

///|
pub(all) struct ProjectWindowConfig {
  title : String
  width : Int
  height : Int
  size_hint : ProjectWindowSizeHint
  titlebar_style : ProjectTitlebarStyle
} derive(Eq, Debug)

///|
pub(all) struct ProjectAppWindowConfig {
  id : String
  window : ProjectWindowConfig
  entry : ProjectEntry
} derive(Eq, Debug)

///|
pub fn ProjectAppWindowConfig::new(
  id : String,
  window : ProjectWindowConfig,
  entry : ProjectEntry,
) -> ProjectAppWindowConfig {
  ProjectAppWindowConfig::{ id, window, entry }
}

///|
pub fn ProjectWindowConfig::new(
  title : String,
  width : Int,
  height : Int,
  size_hint? : ProjectWindowSizeHint = WindowSizeNone,
  titlebar_style? : ProjectTitlebarStyle = TitlebarDefault,
) -> ProjectWindowConfig {
  ProjectWindowConfig::{ title, width, height, size_hint, titlebar_style }
}

///|
pub(all) struct ProjectMetadata {
  product_name : String
  identifier : String?
  version : String?
  description : String?
  license : String?
} derive(Eq, Debug)

///|
pub fn ProjectMetadata::new(
  product_name : String,
  identifier? : String? = None,
  version? : String? = None,
  description? : String? = None,
  license? : String? = None,
) -> ProjectMetadata {
  ProjectMetadata::{ product_name, identifier, version, description, license }
}

///|
pub(all) struct ProjectBackendConfig {
  path : String
  app_package : String
} derive(Eq, Debug)

///|
pub fn ProjectBackendConfig::new(
  path : String,
  app_package : String,
) -> ProjectBackendConfig {
  ProjectBackendConfig::{ path, app_package }
}

///|
pub fn ProjectBackendConfig::path(self : ProjectBackendConfig) -> String {
  self.path
}

///|
pub fn ProjectBackendConfig::app_package(self : ProjectBackendConfig) -> String {
  self.app_package
}

///|
pub(all) struct ProjectFrontendConfig {
  dev_url : String?
  dist : String?
  before_dev : String?
  before_build : String?
  path : String?
} derive(Eq, Debug)

///|
pub fn ProjectFrontendConfig::new(
  dev_url? : String? = None,
  dist? : String? = None,
  before_dev? : String? = None,
  before_build? : String? = None,
  path? : String? = None,
) -> ProjectFrontendConfig {
  ProjectFrontendConfig::{ dev_url, dist, before_dev, before_build, path }
}

///|
pub fn ProjectFrontendConfig::dev_url(self : ProjectFrontendConfig) -> String? {
  self.dev_url
}

///|
pub fn ProjectFrontendConfig::dist(self : ProjectFrontendConfig) -> String? {
  self.dist
}

///|
pub fn ProjectFrontendConfig::before_dev(
  self : ProjectFrontendConfig,
) -> String? {
  self.before_dev
}

///|
pub fn ProjectFrontendConfig::before_build(
  self : ProjectFrontendConfig,
) -> String? {
  self.before_build
}

///|
pub fn ProjectFrontendConfig::path(self : ProjectFrontendConfig) -> String? {
  self.path
}

///|
pub(all) struct ProjectBundleConfig {
  active : Bool
  targets : Array[String]
  icon : Array[String]
  resources : Array[String]
  url_schemes : Array[String]
  document_types : Array[ProjectDocumentType]
  output : String
} derive(Eq, Debug)

///|
pub(all) struct ProjectDocumentType {
  name : String
  extensions : Array[String]
  role : String
} derive(Eq, Debug)

///|
pub fn ProjectDocumentType::new(
  name : String,
  extensions : Array[String],
  role? : String = "Viewer",
) -> ProjectDocumentType {
  ProjectDocumentType::{ name, extensions: extensions.copy(), role }
}

///|
pub fn ProjectBundleConfig::new(
  active? : Bool = false,
  targets? : Array[String] = [],
  icon? : Array[String] = [],
  resources? : Array[String] = [],
  url_schemes? : Array[String] = [],
  document_types? : Array[ProjectDocumentType] = [],
  output? : String = "target/proton-dist",
) -> ProjectBundleConfig {
  ProjectBundleConfig::{
    active,
    targets: copy_strings(targets),
    icon: copy_strings(icon),
    resources: copy_strings(resources),
    url_schemes: copy_strings(url_schemes),
    document_types: document_types.copy(),
    output,
  }
}

///|
pub fn ProjectBundleConfig::active(self : ProjectBundleConfig) -> Bool {
  self.active
}

///|
pub fn ProjectBundleConfig::output(self : ProjectBundleConfig) -> String {
  self.output
}

///|
pub(all) struct ProjectConfig {
  base_dir : String
  window : ProjectWindowConfig
  entry : ProjectEntry
  windows : Array[ProjectAppWindowConfig]
  metadata : ProjectMetadata
  backend : ProjectBackendConfig?
  frontend : ProjectFrontendConfig?
  bundle : ProjectBundleConfig?
  debug : Int
} derive(Eq, Debug)

///|
pub fn ProjectConfig::new(
  base_dir : String,
  window : ProjectWindowConfig,
  entry : ProjectEntry,
  metadata : ProjectMetadata,
  windows? : Array[ProjectAppWindowConfig] = [],
  backend? : ProjectBackendConfig? = None,
  frontend? : ProjectFrontendConfig? = None,
  bundle? : ProjectBundleConfig? = None,
  debug? : Int = 0,
) -> ProjectConfig {
  ProjectConfig::{
    base_dir,
    window,
    entry,
    windows: windows.copy(),
    metadata,
    backend,
    frontend,
    bundle,
    debug,
  }
}

///|
pub fn ProjectConfig::base_dir(self : ProjectConfig) -> String {
  self.base_dir
}

///|
pub fn ProjectConfig::window(self : ProjectConfig) -> ProjectWindowConfig {
  self.window
}

///|
pub fn ProjectConfig::entry(self : ProjectConfig) -> ProjectEntry {
  self.entry
}

///|
/// Returns the primary entry followed by each secondary window entry in
/// declaration order.
pub fn ProjectConfig::entries(self : ProjectConfig) -> Array[ProjectEntry] {
  let entries = [self.entry]
  for window in self.windows {
    entries.push(window.entry)
  }
  entries
}

///|
pub fn ProjectConfig::windows(
  self : ProjectConfig,
) -> Array[ProjectAppWindowConfig] {
  self.windows.copy()
}

///|
pub fn ProjectConfig::metadata(self : ProjectConfig) -> ProjectMetadata {
  self.metadata
}

///|
pub fn ProjectConfig::backend(self : ProjectConfig) -> ProjectBackendConfig? {
  self.backend
}

///|
pub fn ProjectConfig::frontend(self : ProjectConfig) -> ProjectFrontendConfig? {
  self.frontend
}

///|
pub fn ProjectConfig::bundle(self : ProjectConfig) -> ProjectBundleConfig? {
  self.bundle
}

///|
pub fn ProjectConfig::debug(self : ProjectConfig) -> Int {
  self.debug
}

///|
fn copy_strings(values : Array[String]) -> Array[String] {
  let copy : Array[String] = []
  for value in values {
    copy.push(value)
  }
  copy
}

///|
pub(all) struct LoadedProjectConfig {
  config : ProjectConfig
  warnings : Array[String]
} derive(Eq, Debug)

///|
pub fn LoadedProjectConfig::new(
  config : ProjectConfig,
  warnings? : Array[String] = [],
) -> LoadedProjectConfig {
  LoadedProjectConfig::{ config, warnings: copy_strings(warnings) }
}

///|
pub fn LoadedProjectConfig::config(self : LoadedProjectConfig) -> ProjectConfig {
  self.config
}

///|
pub fn LoadedProjectConfig::warnings(
  self : LoadedProjectConfig,
) -> Array[String] {
  self.warnings
}
