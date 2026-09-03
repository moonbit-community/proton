///|
async fn main {
  let app = @proton.html(
    "Process Extension",
    resource,
    width=920,
    height=700,
    debug=true,
  ).capability(@process.capability())
  app.identifier("dev.proton.76-process-extension").run_or_abort()
}
