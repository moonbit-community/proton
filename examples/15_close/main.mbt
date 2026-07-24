///|
fn main {
  @proton.run(() => {
    let html =
      #|<!doctype html>
      #|<html>
      #|  <head><meta charset="utf-8"><title>15 close</title></head>
      #|  <body><h1>15 close</h1></body>
      #|</html>
    @proton.html("15 close", html, width=800, height=600, debug=true).run_or_abort()
  })
}
