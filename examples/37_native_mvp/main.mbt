///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html>
    #|  <head><meta charset="utf-8"><title>37 native mvp</title></head>
    #|  <body><h1>37 native mvp</h1></body>
    #|</html>
  @proton.html("37 native mvp", html, width=800, height=600, debug=true).run_or_abort()
}
