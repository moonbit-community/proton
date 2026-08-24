///|
struct IdentifyPayload {
  label : String
  delay_ms : Int?
} derive(FromJson, ToJson)

///|
pub extend IdentifyPayload with ToJson::{to_json}

///|
pub extend IdentifyPayload with FromJson::{from_json}

///|
struct IdentifyReply {
  label : String
  window : String
} derive(FromJson, ToJson)

///|
pub extend IdentifyReply with ToJson::{to_json}

///|
pub extend IdentifyReply with FromJson::{from_json}

///|
let multi_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/multi-window",
  js_namespace="multi",
)

///|
let identify_command : @proton_contract.Command[IdentifyPayload, IdentifyReply] = multi_contract.command(
  "identify",
)

///|
async fn identify(
  context : @proton.CommandContext,
  payload : IdentifyPayload,
) -> IdentifyReply {
  @async.sleep(payload.delay_ms.unwrap_or(0))
  IdentifyReply::{ label: payload.label, window: context.window_id(), }
}

///|
fn multi_window_extension() -> @proton_extension.Extension {
  @proton_extension.typed(multi_contract, [identify_command.contract_route()], fn(
    registrar,
  ) raise {
    registrar.bind(identify_command, (context, payload) => {
      identify(context, payload)
    })
  })
}

///|
fn page_html(label : String) -> String {
  let html =
    #|<!doctype html>
    #|<html>
    #|  <head>
    #|    <meta charset="utf-8">
    #|    <title>Bridge Multi LABEL</title>
    #|  </head>
    #|  <body>
    #|    <h1>Bridge Multi LABEL</h1>
    #|    <button id="identify">Identify this window</button>
    #|    <pre id="result">Waiting.</pre>
    #|    <script>
    #|      window.__bridgeMultiLabel = "LABEL";
    #|      document.querySelector("#identify").addEventListener("click", async () => {
    #|        const result = await window.__MoonBit__.multi.identify({
    #|          label: window.__bridgeMultiLabel,
    #|        });
    #|        document.querySelector("#result").textContent =
    #|          JSON.stringify(result, null, 2);
    #|      });
    #|    </script>
    #|  </body>
    #|</html>
  html.replace_all(old="LABEL", new=label)
}

///|
async fn main {
  @proton.html(
    "Bridge Multi A",
    page_html("A"),
    width=520,
    height=420,
    debug=true,
  )
  .add_window(
    "secondary",
    "Bridge Multi B",
    @proton.AppEntry::Html(page_html("B")),
    width=520,
    height=420,
    open_on_start=false,
  )
  .capability(@proton_extension.capability(multi_window_extension()), targets=[
    @proton.RendererTarget::entry(),
    @proton.RendererTarget::entry(window="secondary"),
  ])
  .app_lifecycle(
    on_start=async fn(context) { ignore(context.windows().open("secondary")) },
    on_shutdown=fn(_state) {  },
  )
  .run_or_abort()
}
