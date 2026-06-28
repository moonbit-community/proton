///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html>
    #|  <head><meta charset="utf-8"><title>07 inject js</title></head>
    #|  <body><h1>07 inject js</h1></body>
    #|</html>
  @proton.html("07 inject js", html, width=800, height=600, debug=true).run_or_abort()
}
