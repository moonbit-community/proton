///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html>
    #|  <head><meta charset="utf-8"><title>09 dispatch</title></head>
    #|  <body><h1>09 dispatch</h1></body>
    #|</html>
  @proton.html("09 dispatch", html, width=800, height=600, debug=true).run_or_abort()
}
