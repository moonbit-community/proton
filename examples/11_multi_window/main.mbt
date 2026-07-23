///|
fn main {
  @proton.run(() => {
    let html =
      #|<!doctype html>
      #|<html>
      #|  <head><meta charset="utf-8"><title>11 multi window</title></head>
      #|  <body><h1>11 multi window</h1></body>
      #|</html>
    @proton.html("11 multi window", html, width=800, height=600, debug=true).run_or_abort()
  })
}
