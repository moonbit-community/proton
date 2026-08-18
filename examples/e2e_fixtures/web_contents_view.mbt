///|
let wcv_left_url = "data:text/html,<html><head><title>WCV Left</title></head><body><h1>left-marker</h1></body></html>"

///|
let wcv_right_url = "proton://view-right/"

///|
let wcv_right_html =
  #|<!doctype html>
  #|<html>
  #|  <head><meta charset="utf-8"><title>WCV Right</title></head>
  #|  <body><h1>right-marker</h1></body>
  #|</html>

///|
let wcv_host_page =
  #|<!doctype html>
  #|<html>
  #|  <head><meta charset="utf-8"><title>Web Contents View Host</title></head>
  #|  <body><h1>host-marker</h1></body>
  #|</html>

///|
async fn run_web_contents_view_app() -> Result[Unit, String] {
  let view_events : Array[String] = []
  let app = @proton.html(
      "Web Contents View Host",
      wcv_host_page,
      width=640,
      height=480,
      debug=true,
    )
    .window_lifecycle(
      on_ready=fn(context) raise {
        let window = context.handle()
        let left = window.add_view(
          "left",
          @proton.view(wcv_left_url, width=300, height=220, x=10, y=10),
        )
        let right = window.add_view(
          "right",
          @proton.view(
            "about:blank",
            width=300,
            height=220,
            x=330,
            y=10,
            z_order=1,
          ),
        )
        left.load_url(wcv_left_url)
        right.load_html(wcv_right_html, wcv_right_url)
      },
      on_close=fn(_state) {  },
    )
    .on_view_event(fn(_view, event) noraise {
      view_events.push(web_contents_view_event_line(event))
      match @env.get_env_var("PROTON_NATIVE_LOG") {
        Some(native_log) =>
          @mbfs.write_string_to_file(
            native_log + ".view-events",
            view_events.join("\n"),
          ) catch {
            _ => ()
          }
        None => ()
      }
    })
  try {
    app.run()
    Ok(())
  } catch {
    error => Err(error.message())
  }
}

///|
fn web_contents_view_event_line(event : @proton.ViewEvent) -> String {
  match event {
    LoadingChanged(is_loading~) =>
      "view_loading_changed loading=" + is_loading.to_string()
    Navigated(url~) => "view_navigated url=" + url
    TitleUpdated(title~) => "view_title_updated title=" + title
    LoadFailed(url~, error_code~, error_text~) =>
      "view_load_failed url=" +
      url +
      " error_code=" +
      error_code.to_string() +
      " error_text=" +
      error_text
  }
}
