///|
let window_slot : Ref[@proton.WindowHandle?] = Ref(None)

///|
let controls : @proton_contract.Command[String, Json] = @proton_contract.command(
  "traffic_lights",
)

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(controls, (_context, action) => {
    let window = window_slot.val.unwrap()
    match action {
      "custom" => window.set_window_button_position(Some({ x: 24, y: 30, }))
      "origin" => window.set_window_button_position(Some({ x: 0, y: 0, }))
      "reset" => window.set_window_button_position(None)
      "hide" => window.set_window_button_visibility(false)
      "show" => window.set_window_button_visibility(true)
      "resize" => window.set_size(960, 640)
      "minimize" => window.minimize()
      "restore" => window.restore()
      "fullscreen" => window.set_fullscreen(true)
      "windowed" => window.set_fullscreen(false)
      _ => ()
    }
    match window.window_button_position() {
      Some(p) => { "custom": true, "x": p.x, "y": p.y }
      None => { "custom": false }
    }
  })
}

///|
async fn main {
  let page =
    #|<!doctype html><html><head><meta charset="utf-8"><title>Traffic light position</title>
    #|<style>body{margin:0;background:#f3f5f7;color:#243041;font:16px system-ui}header{height:76px;background:#dde5ee;display:flex;align-items:center;padding-left:120px;-webkit-app-region:drag}main{padding:28px}button{padding:10px 16px;margin:4px;border:1px solid #8995a5;border-radius:6px;background:white;font:inherit}pre{padding:16px;background:white}h1{font-size:22px}p{max-width:660px;line-height:1.6}</style></head>
    #|<body><header>Native window buttons</header><main><h1>Traffic light position</h1><p>On macOS Overlay windows, move the native buttons without changing their size or spacing. Other platforms keep their native layout.</p>
    #|<div id="controls"></div><pre id="state">Waiting for bridge…</pre><p>Try resizing, hiding/showing the controls, minimizing/restoring, and entering/exiting fullscreen. Reset returns to the system position.</p></main>
    #|<script>window.probe=async(action='read')=>{const result=await window.__MoonBit__.core.invokeOp('app:traffic_lights',action);document.querySelector('#state').textContent=JSON.stringify(result,null,2);return result};for(const action of ['custom','origin','reset','hide','show','resize','minimize','restore','fullscreen','windowed']){const b=document.createElement('button');b.textContent=action;b.onclick=()=>probe(action).catch(e=>document.querySelector('#state').textContent=String(e));document.querySelector('#controls').append(b)}setTimeout(()=>probe().catch(()=>{}),300)</script></body></html>
  @proton.html(
    "Traffic Light Position",
    page,
    width=800,
    height=520,
    debug=true,
  )
  .titlebar_style(Overlay)
  .traffic_light_position(x=16, y=18)
  .identifier("dev.proton.79-traffic-light-position")
  .commands(register_commands)
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      window_slot.val = Some(window)
      window
    },
    on_close=fn(_) { window_slot.val = None },
  )
  .run_or_abort()
}
