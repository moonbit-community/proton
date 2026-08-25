///|
async fn main {
  let app = @proton.html(
    "MoonBit Async Add Extension",
    resource,
    width=840,
    height=560,
    debug=true,
  ).capability(@proton_extension.capability(extension()))
  app.identifier("dev.proton.38-async-extension-add").run_or_abort()
}
