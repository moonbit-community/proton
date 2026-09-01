///|
struct ControlRequest {
  action : String
} derive(ToJson, FromJson)

///|
pub extend ControlRequest with ToJson::{to_json}

///|
pub extend ControlRequest with FromJson::{from_json}

///|
struct ControlReply {
  ok : Bool
  is_default : Bool
  message : String
} derive(ToJson, FromJson)

///|
pub extend ControlReply with ToJson::{to_json}

///|
pub extend ControlReply with FromJson::{from_json}

///|
let scheme = "proton-control-review"

///|
let contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/app-protocol-process",
  js_namespace="appControlReview",
)

///|
let control_command : @proton_contract.Command[ControlRequest, ControlReply] = contract.command(
  "control",
)

///|
let application_slot : Ref[@proton.ApplicationContext?] = { val: None, }

///|
fn reply(
  context : @proton.ApplicationContext,
  message : String,
  ok? : Bool = true,
) -> ControlReply {
  let is_default = context.is_default_protocol_client(scheme) catch {
    _ => false
  }
  { ok, is_default, message, }
}

///|
fn control(request : ControlRequest) -> ControlReply {
  let context = match application_slot.val {
    Some(context) => context
    None =>
      return {
        ok: false,
        is_default: false,
        message: "Application context is not ready",
      }
  }
  try {
    match request.action {
      "query" => reply(context, "Default protocol state refreshed")
      "register" => {
        let changed = context.set_as_default_protocol_client(scheme)
        reply(
          context,
          if changed {
            "Protocol handler registered"
          } else {
            "Protocol handler was not changed"
          },
          ok=changed,
        )
      }
      "remove" => {
        let removed = context.remove_default_protocol_client(scheme)
        reply(
          context,
          if removed {
            "Protocol handler removed"
          } else {
            "Removal is unavailable or this app is not the default"
          },
          ok=removed,
        )
      }
      "relaunch-quit" => {
        context.relaunch(
          options=@proton.RelaunchOptions(arguments=["--proton-relaunch-review"]),
        )
        context.quit()
        reply(context, "Relaunch scheduled; orderly quit requested")
      }
      "relaunch-exit" => {
        context.relaunch(
          options=@proton.RelaunchOptions(arguments=["--proton-relaunch-review"]),
        )
        context.exit(exit_code=0)
        reply(context, "unreachable")
      }
      "exit-7" => {
        context.exit(exit_code=7)
        reply(context, "unreachable")
      }
      _ => reply(context, "Unknown action", ok=false)
    }
  } catch {
    error => reply(context, error.message(), ok=false)
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(control_command, (_context, request) => control(request))
}

///|
fn page(arguments : String) -> String {
  (
    $|<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Application protocol and process</title>
    $|<style>*{box-sizing:border-box}:root{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#1f292d;background:#e9edef}body{margin:0;min-height:100vh}header{padding:28px 34px;background:#20272b;color:#fff;border-bottom:5px solid #c94f3d}.eyebrow{font:700 11px/1.4 ui-monospace,SFMono-Regular,monospace;color:#75d5b4}h1{margin:6px 0 8px;font-size:29px;letter-spacing:0}header p{margin:0;color:#c7d0d4}main{display:grid;grid-template-columns:1fr 1fr;gap:1px;background:#aab3b7}.panel{min-width:0;padding:26px 30px;background:#fff}.panel h2{margin:0 0 8px;font-size:18px}.panel p{margin:0 0 18px;color:#5b676d;font-size:13px;line-height:1.55}.actions{display:grid;grid-template-columns:1fr 1fr;gap:8px}button{min-height:40px;border:1px solid #718087;background:#f8fafb;color:#20272b;font-weight:700;cursor:pointer}button.primary{background:#256b5a;border-color:#256b5a;color:#fff}button.danger{background:#a43c32;border-color:#a43c32;color:#fff}.state{margin-top:18px;padding:14px;border:1px solid #aab3b7;background:#f4f6f7;font:12px/1.5 ui-monospace,SFMono-Regular,monospace}.state strong{color:#256b5a}.argv{overflow-wrap:anywhere;color:#46545b}.status{grid-column:1/-1;padding:18px 30px;background:#20272b;color:#eaf0f2;font:13px/1.5 ui-monospace,SFMono-Regular,monospace}@media(max-width:720px){main{grid-template-columns:1fr}.panel{padding:22px}.status{grid-column:auto}}</style></head>
    $|<body><header><span class="eyebrow">ELECTRON APP / REVIEW 75</span><h1>Protocol and process control</h1><p>Explicit system mutations and observable relaunch behavior.</p></header><main><section class="panel"><h2>Default protocol client</h2><p>Scheme: <code>\{scheme}</code>. Registration requires a packaged macOS app; Linux requires an installed desktop entry.</p><div class="actions"><button data-action="query">Refresh</button><button class="primary" data-action="register">Register</button><button data-action="remove">Remove</button></div><div class="state">Default handler: <strong id="default-state">unknown</strong></div></section><section class="panel"><h2>Exit and relaunch</h2><p>Relaunch uses <code>--proton-relaunch-review</code>. Immediate exit skips lifecycle shutdown and close interception.</p><div class="actions"><button class="primary" data-action="relaunch-quit">Relaunch + quit</button><button class="danger" data-action="relaunch-exit">Relaunch + exit</button><button class="danger" data-action="exit-7">Exit code 7</button></div><div class="state">Startup argv: <span class="argv">\{arguments}</span></div></section><div id="status" class="status" role="status">Ready. No system setting has been changed.</div></main>
    $|<script>const status=document.querySelector('#status');const state=document.querySelector('#default-state');async function run(action){status.textContent=`${action}...`;try{const reply=await window.__MoonBit__.core.invokeOp('ext:appControlReview/control',{action});state.textContent=reply.is_default?'yes':'no';status.textContent=reply.message}catch(error){status.textContent=String(error)}}document.querySelectorAll('[data-action]').forEach(button=>button.onclick=()=>void run(button.dataset.action));void run('query')</script></body></html>
  )
}

///|
async fn main {
  @proton.html(
    "Application Protocol And Process",
    page(@env.args().join(" ")),
    width=960,
    height=620,
  )
  .load_config()
  .single_instance()
  .url_scheme(scheme)
  .commands(register_commands)
  .app_lifecycle(
    on_start=context => {
      application_slot.val = Some(context)
      context
    },
    on_shutdown=fn(_context) { application_slot.val = None },
  )
  .run_or_abort()
}
