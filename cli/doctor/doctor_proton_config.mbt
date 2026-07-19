///|
fn read_proton_project_config(path : String) -> Result[DoctorAppConfig, String] {
  @proton_config.load_project_config_from_file(path).map(
    doctor_app_config_from_project_config,
  )
}

///|
fn doctor_app_config_from_project_config(
  project : @proton_config.ProjectConfig,
) -> DoctorAppConfig {
  DoctorAppConfig::{
    window: doctor_window_from_project_window(project.window()),
    entry: doctor_entry_from_project_entry(project.entry()),
    debug: project.debug() != 0,
    frontend: project.frontend().map(doctor_frontend_from_project_frontend),
  }
}

///|
fn doctor_window_from_project_window(
  window : @proton_config.ProjectWindowConfig,
) -> DoctorAppWindow {
  DoctorAppWindow::{
    title: window.title,
    width: window.width,
    height: window.height,
    size_hint: doctor_size_hint_from_project_size_hint(window.size_hint),
    titlebar_style: doctor_titlebar_style_from_project_titlebar_style(
      window.titlebar_style,
    ),
  }
}

///|
fn doctor_titlebar_style_from_project_titlebar_style(
  style : @proton_config.ProjectTitlebarStyle,
) -> String {
  match style {
    TitlebarDefault => "default"
    TitlebarOverlay => "overlay"
  }
}

///|
fn doctor_size_hint_from_project_size_hint(
  size_hint : @proton_config.ProjectWindowSizeHint,
) -> String {
  match size_hint {
    WindowSizeNone => "none"
    WindowSizeMin => "min"
    WindowSizeMax => "max"
    WindowSizeFixed => "fixed"
  }
}

///|
fn doctor_entry_from_project_entry(
  entry : @proton_config.ProjectEntry,
) -> DoctorAppEntry {
  match entry {
    Html(value) => DoctorAppEntry::{ kind: "html", value }
    Url(value) => DoctorAppEntry::{ kind: "url", value }
    File(value) => DoctorAppEntry::{ kind: "file", value }
    Asset(value) => DoctorAppEntry::{ kind: "asset", value }
  }
}

///|
fn doctor_frontend_from_project_frontend(
  frontend : @proton_config.ProjectFrontendConfig,
) -> DoctorFrontendConfig {
  DoctorFrontendConfig::{
    before_dev: frontend.before_dev(),
    before_build: frontend.before_build(),
    dist: frontend.dist(),
    dev_url: frontend.dev_url(),
    cwd: frontend.cwd(),
  }
}
