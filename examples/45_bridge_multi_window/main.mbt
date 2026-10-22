///|
struct IdentifyPayload {
  label : String
  delay_ms : Int32?
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
fn multi_window_extension(
  create_window : async () -> String,
) -> @proton_extension.Extension {
  @proton_extension.typed(multi_contract, fn(registrar) raise {
    let create : @proton_contract.Command[Unit, String] = multi_contract.command(
      "create_window",
    )
    registrar.bind(create, (_, _) => create_window())
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
    #|    <button id="create">New window</button>
    #|    <button id="identify">Identify this window</button>
    #|    <pre id="result">Waiting.</pre>
    #|    <script>
    #|      window.__bridgeMultiLabel = "LABEL";
    #|      document.querySelector("#create").addEventListener("click", async () => {
    #|        try {
    #|          const id = await window.__MoonBit__.multi.create_window(null);
    #|          document.querySelector("#result").textContent = `Created ${id}`;
    #|        } catch (error) {
    #|          document.querySelector("#result").textContent = String(error);
    #|        }
    #|      });
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
  let config = @proton.WindowConfig(
    "Bridge Multi B",
    @proton.AppEntry::Html(page_html("B")),
    width=520,
    height=420,
  )
  let windows : Ref[@proton.WindowManager?] = Ref(None)
  let next_id = Ref(0)
  let extension = multi_window_extension(() => {
    next_id.val += 1
    let id = "chat-" + next_id.val.to_string()
    ignore(windows.val.unwrap().create(id, config))
    id
  })
  @proton.html(
    "Bridge Multi A",
    page_html("A"),
    width=520,
    height=420,
    debug=true,
  )
  ..identifier("dev.proton.45-bridge-multi-window")
  ..single_instance()
  ..capability(@proton_extension.capability(extension), targets=[
    @proton.RendererTarget::entry(),
    @proton.RendererTarget::entry(window="secondary"),
    @proton.RendererTarget::entry_prefix("chat-"),
  ])
  ..setup(context => {
    windows.val = Some(context.windows())
    ignore(context.windows().create("secondary", config))
  })
  .run_or_abort()
}
