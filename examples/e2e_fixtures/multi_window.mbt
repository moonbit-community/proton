///|
struct MultiWindowIdentifyPayload {
  label : String
  delay_ms : Int?
} derive(FromJson)

///|
pub extend MultiWindowIdentifyPayload with FromJson::{from_json}

///|
struct MultiWindowIdentifyReply {
  label : String
  window : String
  page_instance : String
} derive(ToJson)

///|
pub extend MultiWindowIdentifyReply with ToJson::{to_json}

///|
let multi_window_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="e2e/multi-window",
  js_namespace="multi",
)

///|
let multi_window_identify : @proton_contract.Command[
  MultiWindowIdentifyPayload,
  MultiWindowIdentifyReply,
] = multi_window_contract.command("identify")

///|
fn multi_window_extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    multi_window_contract,
    [multi_window_identify.contract_route()],
    fn(registrar) raise {
      registrar.bind(multi_window_identify, async fn(context, payload) {
        @async.sleep(payload.delay_ms.unwrap_or(0))
        MultiWindowIdentifyReply::{
          label: payload.label,
          window: context.window_id(),
          page_instance: context.page_instance().unwrap_or(context.window_id()),
        }
      })
    },
  )
}

///|
fn multi_window_page_html(label : String) -> String {
  let html =
    #|<!doctype html>
    #|<html>
    #|  <head><meta charset="utf-8"><title>Bridge Multi LABEL</title></head>
    #|  <body>
    #|    <h1>Bridge Multi LABEL</h1>
    #|    <script>window.__bridgeMultiLabel = "LABEL";</script>
    #|  </body>
    #|</html>
  html.replace_all(old="LABEL", new=label)
}

///|
async fn run_multi_window_bridge() -> Result[Unit, String] {
  let app = @proton.html(
      "Bridge Multi A",
      multi_window_page_html("A"),
      width=520,
      height=420,
      debug=true,
    )
    .add_window(
      "secondary",
      "Bridge Multi B",
      @proton.AppEntry::Html(multi_window_page_html("B")),
      width=520,
      height=420,
      open_on_start=true,
    )
    .capability(@proton_extension.capability(multi_window_extension()), targets=[
      @proton.RendererTarget::entry(),
      @proton.RendererTarget::entry(window="secondary"),
    ])
  try {
    app.run()
    Ok(())
  } catch {
    error => Err(error.message())
  }
}
