///|
async fn main {
  let app = @proton.html(
    "MoonBit App Runtime + Auto Launch",
    resource,
    width=980,
    height=700,
    debug=true,
  ).extension(@auto_launch.extension())
  app.run_or_abort()
}
