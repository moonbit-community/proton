///|
async fn main {
  let app = @proton.html(
      "MoonBit Ops Runtime",
      resource,
      width=980,
      height=720,
      debug=true,
    )
    .capability(@fs.capability([@fs.PermissionRoot::new(".", ["readdir"])]))
    .capability(@path.capability())
  app.run_or_abort()
}
