///|
pub(all) enum ProjectWindowSizeHint {
  WindowSizeNone
  WindowSizeMin
  WindowSizeMax
  WindowSizeFixed
} derive(Eq, Debug)

///|
pub extend ProjectWindowSizeHint with Eq::{not_equal, equal}

///|
pub extend ProjectWindowSizeHint with Debug::{to_repr}

///|
pub(all) enum ProjectTitlebarStyle {
  TitlebarDefault
  TitlebarOverlay
} derive(Eq, Debug)

///|
pub extend ProjectTitlebarStyle with Eq::{not_equal, equal}

///|
pub extend ProjectTitlebarStyle with Debug::{to_repr}

///|
pub(all) enum ProjectEntry {
  Html(String)
  Url(String)
  File(String)
  Asset(String)
} derive(Eq, Debug)

///|
pub extend ProjectEntry with Eq::{not_equal, equal}

///|
pub extend ProjectEntry with Debug::{to_repr}

///|
pub(all) struct ProjectWindowConfig {
  title : String
  width : Int
  height : Int
  size_hint : ProjectWindowSizeHint
  titlebar_style : ProjectTitlebarStyle
} derive(Eq, Debug)

///|
pub extend ProjectWindowConfig with Eq::{not_equal, equal}

///|
pub extend ProjectWindowConfig with Debug::{to_repr}

///|
pub(all) struct ProjectAppWindowConfig {
  id : String
  window : ProjectWindowConfig
  entry : ProjectEntry
  open_on_start : Bool
} derive(Eq, Debug)

///|
pub extend ProjectAppWindowConfig with Eq::{not_equal, equal}

///|
pub extend ProjectAppWindowConfig with Debug::{to_repr}

///|
/// One renderer capability grant from `proton.project.json`.
///
/// `window` is `main` or a declared secondary window id. `origin` is `app`
/// for bundled Proton pages or `entry` for the configured window entry.
/// Extension-specific restrictions live in `scope`.
pub(all) struct ProjectPermissionGrant {
  window : String
  origin : String
  extension : String
  scope : Json
} derive(Eq, Debug)

///|
pub extend ProjectPermissionGrant with Eq::{not_equal, equal}

///|
pub extend ProjectPermissionGrant with Debug::{to_repr}

///|
pub fn ProjectPermissionGrant::new(
  window : String,
  origin : String,
  extension : String,
  scope? : Json = Json::empty_object(),
) -> ProjectPermissionGrant {
  ProjectPermissionGrant::{ window, origin, extension, scope }
}

///|
pub fn ProjectAppWindowConfig::new(
  id : String,
  window : ProjectWindowConfig,
  entry : ProjectEntry,
  open_on_start? : Bool = true,
) -> ProjectAppWindowConfig {
  ProjectAppWindowConfig::{ id, window, entry, open_on_start }
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
pub extend ProjectMetadata with Eq::{not_equal, equal}

///|
pub extend ProjectMetadata with Debug::{to_repr}

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
pub extend ProjectBackendConfig with Eq::{not_equal, equal}

///|
pub extend ProjectBackendConfig with Debug::{to_repr}

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
pub extend ProjectFrontendConfig with Eq::{not_equal, equal}

///|
pub extend ProjectFrontendConfig with Debug::{to_repr}

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
/// Signing settings for files copied through `bundle.resources`.
pub(all) struct ProjectSignConfig {
  binaries : Array[String]
} derive(Eq, Debug)

///|
pub extend ProjectSignConfig with Eq::{not_equal, equal}

///|
pub extend ProjectSignConfig with Debug::{to_repr}

///|
/// Creates signing settings for package-relative resource binaries.
pub fn ProjectSignConfig::new(
  binaries? : Array[String] = [],
) -> ProjectSignConfig {
  ProjectSignConfig::{ binaries: copy_strings(binaries) }
}

///|
/// Returns the project paths whose packaged copies must be signed.
pub fn ProjectSignConfig::binaries(self : ProjectSignConfig) -> Array[String] {
  copy_strings(self.binaries)
}

///|
pub(all) struct ProjectBundleConfig {
  active : Bool
  targets : Array[String]
  icon : Array[String]
  resources : Array[String]
  sign : ProjectSignConfig?
  url_schemes : Array[String]
  document_types : Array[ProjectDocumentType]
  output : String
} derive(Eq, Debug)

///|
pub extend ProjectBundleConfig with Eq::{not_equal, equal}

///|
pub extend ProjectBundleConfig with Debug::{to_repr}

///|
pub(all) struct ProjectDocumentType {
  name : String
  extensions : Array[String]
  role : String
} derive(Eq, Debug)

///|
pub extend ProjectDocumentType with Eq::{not_equal, equal}

///|
pub extend ProjectDocumentType with Debug::{to_repr}

///|
pub fn ProjectDocumentType::new(
  name : String,
  extensions : Array[String],
  role? : String = "Viewer",
) -> ProjectDocumentType {
  ProjectDocumentType::{ name, extensions: extensions.copy(), role }
}

///|
pub fn ProjectDocumentType::extensions(
  self : ProjectDocumentType,
) -> Array[String] {
  self.extensions.copy()
}

///|
pub fn ProjectBundleConfig::new(
  active? : Bool = false,
  targets? : Array[String] = [],
  icon? : Array[String] = [],
  resources? : Array[String] = [],
  sign? : ProjectSignConfig? = None,
  url_schemes? : Array[String] = [],
  document_types? : Array[ProjectDocumentType] = [],
  output? : String = "dist",
) -> ProjectBundleConfig {
  ProjectBundleConfig::{
    active,
    targets: copy_strings(targets),
    icon: copy_strings(icon),
    resources: copy_strings(resources),
    sign,
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
  updater : ProjectUpdaterConfig?
  permissions : Array[ProjectPermissionGrant]
  debug : Int
  single_instance : Bool
} derive(Eq, Debug)

///|
pub extend ProjectConfig with Eq::{not_equal, equal}

///|
pub extend ProjectConfig with Debug::{to_repr}

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
  updater? : ProjectUpdaterConfig? = None,
  permissions? : Array[ProjectPermissionGrant] = [],
  debug? : Int = 0,
  single_instance? : Bool = false,
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
    updater,
    permissions: permissions.copy(),
    debug,
    single_instance,
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
pub fn ProjectConfig::updater(self : ProjectConfig) -> ProjectUpdaterConfig? {
  self.updater
}

///|
pub fn ProjectConfig::bundle(self : ProjectConfig) -> ProjectBundleConfig? {
  self.bundle
}

///|
pub fn ProjectConfig::permissions(
  self : ProjectConfig,
) -> Array[ProjectPermissionGrant] {
  self.permissions.copy()
}

///|
pub fn ProjectConfig::single_instance(self : ProjectConfig) -> Bool {
  self.single_instance
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
pub extend LoadedProjectConfig with Eq::{not_equal, equal}

///|
pub extend LoadedProjectConfig with Debug::{to_repr}

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

///|
/// The application's update channel, as declared in `proton.project.json`.
///
/// This carries only what the runtime needs in order to decide whether to
/// check, and whom to trust when it does. No private key material appears
/// here, or anywhere else the framework can reach.
pub(all) struct ProjectUpdaterConfig {
  active : Bool
  endpoint : String
  public_keys : Array[String]
  check_on_launch : Bool
  freshness_days : Int
} derive(Eq, Debug)

///|
pub extend ProjectUpdaterConfig with Eq::{not_equal, equal}

///|
pub extend ProjectUpdaterConfig with Debug::{to_repr}

///|
pub fn ProjectUpdaterConfig::new(
  endpoint : String,
  public_keys : Array[String],
  active? : Bool = true,
  check_on_launch? : Bool = true,
  freshness_days? : Int = 30,
) -> ProjectUpdaterConfig {
  ProjectUpdaterConfig::{
    active,
    endpoint,
    public_keys: copy_strings(public_keys),
    check_on_launch,
    freshness_days,
  }
}

///|
pub fn ProjectUpdaterConfig::endpoint(self : ProjectUpdaterConfig) -> String {
  self.endpoint
}

///|
pub fn ProjectUpdaterConfig::public_keys(
  self : ProjectUpdaterConfig,
) -> Array[String] {
  copy_strings(self.public_keys)
}

///|
pub fn ProjectUpdaterConfig::is_active(self : ProjectUpdaterConfig) -> Bool {
  self.active
}

///|
pub fn ProjectUpdaterConfig::checks_on_launch(
  self : ProjectUpdaterConfig,
) -> Bool {
  self.check_on_launch
}

///|
pub fn ProjectUpdaterConfig::freshness_days(self : ProjectUpdaterConfig) -> Int {
  self.freshness_days
}
