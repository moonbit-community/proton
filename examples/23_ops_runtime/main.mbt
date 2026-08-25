///|
async fn main {
  let app = @proton.html(
      "MoonBit Ops Runtime",
      resource,
      width=980,
      height=720,
      debug=true,
    )
    .capability(@fs.capability([@fs.PermissionRoot(".", ["readdir"])]))
    .capability(@path.capability())
  app.identifier("dev.proton.23-ops-runtime").run_or_abort()
}
