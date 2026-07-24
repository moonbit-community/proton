///|
fn main {
  @proton.run(() => {
    let html =
      #|<!doctype html>
      #|<html>
      #|  <head><meta charset="utf-8"><title>43 native bind smoke</title></head>
      #|  <body><h1>43 native bind smoke</h1></body>
      #|</html>
    @proton.html(
      "43 native bind smoke",
      html,
      width=800,
      height=600,
      debug=true,
    ).run_or_abort()
  })
}
