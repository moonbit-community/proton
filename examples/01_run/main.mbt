///|
fn main {
  @proton.run(() => {
    let html =
      #|<!doctype html>
      #|<html>
      #|  <head><meta charset="utf-8"><title>01 run</title></head>
      #|  <body><h1>01 run</h1></body>
      #|</html>
    @proton.html("01 run", html, width=800, height=600, debug=true).run_or_abort()
  })
}
