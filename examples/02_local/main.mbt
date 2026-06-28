///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html>
    #|  <head><meta charset="utf-8"><title>02 local</title></head>
    #|  <body><h1>02 local</h1></body>
    #|</html>
  @proton.html("02 local", html, width=800, height=600, debug=true).run_or_abort()
}
