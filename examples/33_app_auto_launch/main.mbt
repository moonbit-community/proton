///|
async fn main {
  let app = @app.html(
    "MoonBit App Runtime + Auto Launch",
    980,
    700,
    resource,
    debug=1,
  ).command(@auto_launch.generated_app_command_extension())
  app.run_or_abort()
}
