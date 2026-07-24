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
pub(all) struct ProjectFrontendConfig {
  dev_url : String?
  dist : String?
  before_dev : String?
  before_build : String?
  cwd : String?
} derive(Eq, Debug)

///|
pub fn ProjectFrontendConfig::new(
  dev_url? : String? = None,
  dist? : String? = None,
  before_dev? : String? = None,
  before_build? : String? = None,
  cwd? : String? = None,
) -> ProjectFrontendConfig {
  ProjectFrontendConfig::{ dev_url, dist, before_dev, before_build, cwd }
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
pub fn ProjectFrontendConfig::cwd(self : ProjectFrontendConfig) -> String? {
  self.cwd
}

///|
pub(all) struct ProjectBundleConfig {
  active : Bool
  targets : Array[String]
  icon : Array[String]
  resources : Array[String]
  output : String
} derive(Eq, Debug)

///|
pub fn ProjectBundleConfig::new(
  active? : Bool = false,
  targets? : Array[String] = [],
  icon? : Array[String] = [],
  resources? : Array[String] = [],
  output? : String = "target/proton-dist",
) -> ProjectBundleConfig {
  ProjectBundleConfig::{
    active,
    targets: copy_strings(targets),
    icon: copy_strings(icon),
    resources: copy_strings(resources),
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
  metadata : ProjectMetadata
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
  frontend? : ProjectFrontendConfig? = None,
  bundle? : ProjectBundleConfig? = None,
  debug? : Int = 0,
) -> ProjectConfig {
  ProjectConfig::{ base_dir, window, entry, metadata, frontend, bundle, debug }
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
pub fn ProjectConfig::metadata(self : ProjectConfig) -> ProjectMetadata {
  self.metadata
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
