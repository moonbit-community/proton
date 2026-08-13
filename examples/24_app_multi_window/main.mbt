///|
async fn main {
  @proton.file(
    "MoonBit Multi-Window",
    "24_app_multi_window/main_window.html",
    width=980,
    height=680,
    debug=true,
  ).run_or_abort()
}
