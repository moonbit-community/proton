///|
async fn main {
  let app = @lepus.html(
    "MoonBit Async Add Extension",
    840,
    560,
    resource,
    debug=1,
  ).command(generated_app_command_extension())
  app.run_or_abort()
}
