///|
let page =
  #|<!doctype html>
  #|<html>
  #|  <head>
  #|    <meta charset="utf-8" />
  #|    <title>Browser Control</title>
  #|  </head>
  #|  <body>
  #|    <h1>Browser Control</h1>
  #|    <p><a href="https://example.com/">Navigate to example.com</a></p>
  #|    <p><button id="popup">Open popup in this window</button></p>
  #|    <p><a download="proton.txt" href="data:text/plain,Hello%20from%20Proton">Download file</a></p>
  #|    <p><button id="media">Request microphone</button></p>
  #|    <script>
  #|      document.querySelector("#popup").onclick = () => {
  #|        window.open("https://example.com/popup", "_blank");
  #|      };
  #|      document.querySelector("#media").onclick = async () => {
  #|        await navigator.mediaDevices.getUserMedia({ audio: true });
  #|      };
  #|    </script>
  #|  </body>
  #|</html>
  #|

///|
async fn main {
  @proton.html("Browser Control", page, debug=true)
  .on_navigation_request(fn(_browser, request) {
    println("navigation: \{request.http_method} \{request.url}")
    @proton.NavigationDecision::Allow
  })
  .on_popup_request(fn(_browser, request) {
    println("popup: \{request.url}")
    @proton.PopupDecision::OpenInCurrent
  })
  .on_download_request(fn(_browser, request) {
    println("download: \{request.suggested_name}")
    @proton.DownloadDecision::ShowSaveDialog
  })
  .on_certificate_error(fn(_browser, request) {
    println("certificate error: \{request.error_code} \{request.url}")
    @proton.BrowserPermissionDecision::Deny
  })
  .on_media_permission_request(fn(_browser, request) {
    println("media permission: \{request.origin}")
    @proton.BrowserPermissionDecision::Deny
  })
  .on_download_event(fn(_browser, event) {
    println("download \{event.id}: \{event.state} \{event.percent}%")
  })
  .on_browser_event(fn(browser, event) noraise {
    println("browser event: \{Repr(event)}")
    let state = browser.state() catch {
      error => {
        println("browser state unavailable: \{Repr(error)}")
        return
      }
    }
    println(
      "browser state: loading=\{state.is_loading} back=\{state.can_go_back} forward=\{state.can_go_forward} title=\{state.title} url=\{state.url}",
    )
  })
  .identifier("dev.proton.50-browser-control")
  .run_or_abort()
}
