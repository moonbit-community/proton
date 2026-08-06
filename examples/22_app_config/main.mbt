///|
async fn main {
  @proton.install_event_loop()
  @proton.config("22_app_config/moon.proton").run_or_abort()
}
