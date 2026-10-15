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
  #|    <p><a href="https://expired.badssl.com/">Test certificate rejection (network required)</a></p>
  #|    <p><button id="media">Request microphone</button></p>
  #|    <p id="status">Decisions and observers are printed in the terminal.</p>
  #|    <script>
  #|      document.querySelector("#popup").onclick = () => {
  #|        window.open("https://example.com/popup", "_blank");
  #|      };
  #|      document.querySelector("#media").onclick = async () => {
  #|        try {
  #|          const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  #|          stream.getTracks().forEach(track => track.stop());
  #|          document.querySelector("#status").textContent = "Microphone allowed";
  #|        } catch (error) {
  #|          document.querySelector("#status").textContent = `Microphone rejected: ${error.name}`;
  #|        }
  #|      };
  #|    </script>
  #|  </body>
  #|</html>
  #|

///|
let session_review_started : Ref[Bool] = { val: false, }

///|
async fn review_session(browser : @proton.WebContentsHandle) -> Unit noraise {
  let session = browser.session()
  session.set_cookie(
    "https://example.com/",
    "proton_review",
    "active",
    secure=true,
    same_site=@proton.CookieSameSite::Lax,
  ) catch {
    error => {
      println("set cookie failed: \{error.message()}")
      return
    }
  }
  let cookies = session.get_cookies(
    url="https://example.com/",
    include_http_only=true,
  ) catch {
    error => {
      println("get cookies failed: \{error.to_string()}")
      return
    }
  }
  println("session cookies: \{Repr(cookies)}")
  session.flush_cookies() catch {
    error => println("flush cookies failed: \{error.message()}")
  }
  session.clear_cache() catch {
    error => println("clear cache failed: \{error.message()}")
  }
  session.delete_cookies(url="https://example.com/", name="proton_review") catch {
    error => println("delete cookie failed: \{error.message()}")
  }
}

///|
async fn main {
  @proton.App(
    @proton.WindowConfig(
      "Browser Control",
      @proton.AppEntry::Html(page),
      web_contents_policy=@proton.WebContentsPolicy(new_window_handler=fn(
        _browser,
        request,
      ) {
        println("new window: \{request.url}")
        @proton.NewWindowDecision::OpenInCurrent
      }),
    ),
  )
  ..debug()
  // These initial decisions are replaced below, not combined with the replacements.
  ..set_download_handler(fn(_, _) {
    println("ERROR: replaced download handler ran")
    @proton.DownloadDecision::Deny
  })
  ..set_certificate_error_handler(fn(_, _) {
    println("ERROR: replaced certificate handler ran")
    @proton.BrowserPermissionDecision::Deny
  })
  ..set_media_permission_handler(fn(_, _) {
    println("ERROR: replaced media handler ran")
    @proton.BrowserPermissionDecision::Deny
  })
  ..set_download_handler(fn(_browser, request) {
    println("download: \{request.suggested_name}")
    @proton.DownloadDecision::ShowSaveDialog
  })
  ..set_certificate_error_handler(fn(_browser, request) {
    println("certificate error: \{request.error_code} \{request.url}")
    @proton.BrowserPermissionDecision::Deny
  })
  ..set_media_permission_handler(fn(_browser, request) {
    println("media permission: \{request.origin}")
    @proton.BrowserPermissionDecision::Deny
  })
  ..on_download_event(fn(_browser, event) {
    println("download \{event.id}: \{event.state} \{event.percent}%")
  })
  ..on_web_contents_event(async fn(browser, event) noraise {
    if browser.view_id() is Some(_) {
      return
    }
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
    if event is @proton.WebContentsEvent::Navigated(url~) &&
      url.has_prefix("https://example.com") &&
      !session_review_started.val {
      session_review_started.val = true
      review_session(browser)
    }
  })
  // Both observers receive the event; registration does not replace the first.
  ..on_web_contents_event(fn(browser, event) {
    println("second observer [\{browser.window_id()}]: \{Repr(event)}")
  })
  ..identifier("dev.proton.50-browser-control")
  .run_or_abort()
}
