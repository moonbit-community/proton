///|
async fn main {
  let app = @lepus.html("Lepus Attribute Codegen", 840, 560, resource, debug=1).command(
    generated_app_command_extension(),
  )
  app.run_or_abort()
}
