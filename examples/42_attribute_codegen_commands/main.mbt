///|
async fn main {
  @proton.install_event_loop()
  let app = @proton.html(
    "Proton Attribute Codegen",
    resource,
    width=840,
    height=560,
    debug=true,
  ).expose(extension())
  app.run_or_abort()
}
