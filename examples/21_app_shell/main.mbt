///|
async fn main {
  let app = @lepus.html(
    "MoonBit App Runtime + Shell",
    resource,
    width=860,
    height=620,
    debug=true,
  ).extension(@shell.extension())
  app.run_or_abort()
}
