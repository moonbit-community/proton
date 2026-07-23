///|
fn main {
  @proton.run(() => {
    let html =
      #|<!doctype html>
      #|<html>
      #|  <head><meta charset="utf-8"><title>14 beforeunload</title></head>
      #|  <body><h1>14 beforeunload</h1></body>
      #|</html>
    @proton.html("14 beforeunload", html, width=800, height=600, debug=true).run_or_abort()
  })
}
