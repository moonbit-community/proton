///|
// The minimal web contents view example: a sidebar host page on the left and
// an embedded browser view filling the rest of the window, all declarative.

///|
let sidebar =
  #|<!doctype html>
  #|<html>
  #|  <body style="margin:0;width:288px;height:100vh;background:#f5f5f7;font-family:-apple-system,sans-serif;-webkit-app-region:drag">
  #|    <h1 style="font-size:15px;padding:36px 16px 0">Built-in Browser</h1>
  #|    <p style="font-size:12px;color:#6e6e73;padding:0 16px">
  #|      The area on the right is a web contents view.
  #|    </p>
  #|  </body>
  #|</html>
  #|

///|
async fn main {
  @proton.html("Minimal View", sidebar, width=1120, height=720, debug=true)
  .with_view(
    "browser",
    @proton.view("https://example.com/", width=832, height=720, x=288),
  )
  .run_or_abort()
}
