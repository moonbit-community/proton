///|
async fn main {
  let app = @lepus.html(
    "MoonBit App Runtime + Shell",
    860,
    620,
    resource,
    debug=1,
  ).command(@shell.generated_app_command_extension())
  app.run_or_abort()
}
