///|
async fn main {
  let app = @proton.html(
    "MoonBit App Runtime + Keep Awake",
    resource,
    width=920,
    height=680,
    debug=true,
  ).capability(@keepawake.capability())
  app.run_or_abort()
}
