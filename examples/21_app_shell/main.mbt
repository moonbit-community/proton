///|
async fn main {
  let app = @proton.html(
    "MoonBit App Runtime + Shell",
    resource,
    width=860,
    height=620,
    debug=true,
  ).capability(@shell.capability())
  app.identifier("dev.proton.21-app-shell").run_or_abort()
}
