///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html>
    #|  <head><meta charset="utf-8"><title>05 alert</title></head>
    #|  <body><h1>05 alert</h1></body>
    #|</html>
  @proton.html("05 alert", html, width=800, height=600, debug=true).run_or_abort()
}
