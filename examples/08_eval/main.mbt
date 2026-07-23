///|
fn main {
  @proton.run(() => {
    let html =
      #|<!doctype html>
      #|<html>
      #|  <head><meta charset="utf-8"><title>08 eval</title></head>
      #|  <body><h1>08 eval</h1></body>
      #|</html>
    @proton.html("08 eval", html, width=800, height=600, debug=true).run_or_abort()
  })
}
