///|
pub fn load_proton_manifest_from_file(
  path : String,
) -> LoadedAppManifest raise BootstrapError {
  load_config_manifest_from_file(path)
}

///|
pub fn load_config_manifest_from_file(
  path : String,
) -> LoadedAppManifest raise BootstrapError {
  load_proton_project_config_from_file(path).manifest()
}

///|
pub fn load_proton_project_config_from_file(
  path : String,
) -> ProtonProjectConfig raise BootstrapError {
  let project = @proton_config.load_project_config_from_file(path) catch {
    error => raise ProjectConfig(error)
  }
  proton_project_config_from_project_config(project)
}

///|
pub fn load_proton_project_summary_from_file(
  path : String,
) -> Json raise BootstrapError {
  load_proton_project_config_from_file(path).to_summary_json()
}

///|
fn proton_project_config_from_project_config(
  project : @proton_config.ProjectConfig,
) -> ProtonProjectConfig {
  let loaded = LoadedAppManifest::new(
    @manifest.AppManifest::new(
      proton_window_from_project_window(project.window()),
      proton_entry_from_project_entry(project.entry()),
      debug=project.debug(),
    ),
    base_dir=Some(project.base_dir()),
  )
  ProtonProjectConfig::new(
    loaded,
    proton_metadata_from_project_metadata(project.metadata()),
    frontend=project.frontend().map(proton_frontend_from_project_frontend),
    bundle=project.bundle().map(proton_bundle_from_project_bundle),
  )
}

///|
fn proton_window_from_project_window(
  window : @proton_config.ProjectWindowConfig,
) -> @manifest.WindowManifest {
  @manifest.WindowManifest::new(
    window.title,
    window.width,
    window.height,
    size_hint=proton_size_hint_from_project_size_hint(window.size_hint),
    titlebar_style=proton_titlebar_style_from_project_titlebar_style(
      window.titlebar_style,
    ),
  )
}

///|
fn proton_titlebar_style_from_project_titlebar_style(
  style : @proton_config.ProjectTitlebarStyle,
) -> @manifest.TitlebarStyle {
  match style {
    TitlebarDefault => @manifest.TitlebarStyle::Default
    TitlebarOverlay => @manifest.TitlebarStyle::Overlay
  }
}

///|
fn proton_size_hint_from_project_size_hint(
  size_hint : @proton_config.ProjectWindowSizeHint,
) -> @manifest.WindowSizeHint {
  match size_hint {
    WindowSizeNone => @manifest.WindowSizeHint::None
    WindowSizeMin => @manifest.WindowSizeHint::Min
    WindowSizeMax => @manifest.WindowSizeHint::Max
    WindowSizeFixed => @manifest.WindowSizeHint::Fixed
  }
}

///|
fn proton_entry_from_project_entry(
  entry : @proton_config.ProjectEntry,
) -> @manifest.AppEntry {
  match entry {
    Html(value) => @manifest.AppEntry::Html(value)
    Url(value) => @manifest.AppEntry::Url(value)
    File(value) => @manifest.AppEntry::File(value)
    Asset(value) => @manifest.AppEntry::Asset(value)
  }
}

///|
fn proton_metadata_from_project_metadata(
  metadata : @proton_config.ProjectMetadata,
) -> ProtonAppMetadata {
  ProtonAppMetadata::new(
    metadata.product_name,
    identifier=metadata.identifier,
    version=metadata.version,
    description=metadata.description,
    license=metadata.license,
  )
}

///|
fn proton_frontend_from_project_frontend(
  frontend : @proton_config.ProjectFrontendConfig,
) -> ProtonFrontendConfig {
  ProtonFrontendConfig::new(
    dev_url=frontend.dev_url(),
    dist=frontend.dist(),
    before_dev=frontend.before_dev(),
    before_build=frontend.before_build(),
    cwd=frontend.cwd(),
  )
}

///|
fn proton_bundle_from_project_bundle(
  bundle : @proton_config.ProjectBundleConfig,
) -> ProtonBundleConfig {
  ProtonBundleConfig::new(
    active=bundle.active,
    targets=bundle.targets,
    icon=bundle.icon,
    resources=bundle.resources,
    output=bundle.output(),
  )
}
