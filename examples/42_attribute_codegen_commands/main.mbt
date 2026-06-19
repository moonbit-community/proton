///|
async fn main {
  let app = @lepus.html(
    "Lepus Attribute Codegen",
    resource,
    width=840,
    height=560,
    debug=true,
  ).extension(extension())
  app.run_or_abort()
}
