///|
fn main {
  @proton.run(() => {
    let html =
      #|<!doctype html>
      #|<html>
      #|  <head><meta charset="utf-8"><title>10 bind</title></head>
      #|  <body><h1>10 bind</h1></body>
      #|</html>
    @proton.html("10 bind", html, width=800, height=600, debug=true).run_or_abort()
  })
}
