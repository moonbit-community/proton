///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html>
    #|  <head><meta charset="utf-8"><title>04 user agent</title></head>
    #|  <body><h1>04 user agent</h1></body>
    #|</html>
  @proton.html("04 user agent", html, width=800, height=600, debug=true).run_or_abort()
}
