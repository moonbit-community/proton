///|
async fn main {
  @proton.install_event_loop()
  let app = @proton.html(
    "MoonBit App Runtime + Shell",
    resource,
    width=860,
    height=620,
    debug=true,
  ).expose(@shell.extension())
  app.run_or_abort()
}
