///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html lang="en">
    #|  <head>
    #|    <meta charset="utf-8">
    #|    <meta name="viewport" content="width=device-width, initial-scale=1">
    #|    <title>Proton App</title>
    #|    <style>
    #|      :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
    #|      body { display: grid; min-height: 100vh; margin: 0; place-items: center; }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <h1>Proton App</h1>
    #|      <p>Your minimal Proton app is running.</p>
    #|    </main>
    #|  </body>
    #|</html>
  @proton.html("Proton App", html, width=960, height=640)
  ..config(@proton.load_config())
  .run_or_abort()
}
