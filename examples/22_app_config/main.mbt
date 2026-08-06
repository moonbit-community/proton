///|
async fn main {
  @proton.install_event_loop()
  @proton.config("22_app_config/proton.project.json").run_or_abort()
}
