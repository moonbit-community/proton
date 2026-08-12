///|
fn main {
  @proton.run(() => {
    @proton.config("22_app_config/proton.project.json").run_or_abort()
  })
}
