///|
fn main {
  @proton.run(() => {
    let html =
      #|<!doctype html>
      #|<html>
      #|  <head><meta charset="utf-8"><title>06 onload</title></head>
      #|  <body><h1>06 onload</h1></body>
      #|</html>
    @proton.html("06 onload", html, width=800, height=600, debug=true).run_or_abort()
  })
}
