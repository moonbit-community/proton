///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html>
    #|  <head><meta charset="utf-8"><title>03 remote</title></head>
    #|  <body><h1>03 remote</h1></body>
    #|</html>
  @proton.html("03 remote", html, width=800, height=600, debug=true).run_or_abort()
}
