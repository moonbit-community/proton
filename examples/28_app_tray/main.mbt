///|
async fn main {
  let app = @app.html("MoonBit App Runtime + Tray", 940, 720, resource, debug=1).command(
    @tray.generated_app_command_extension(),
  )
  app.run_or_abort()
}
