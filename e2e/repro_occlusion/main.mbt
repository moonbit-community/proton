///|
#derive(ToJson)
struct NativeState {
  command : String
  minimized : Bool
  visible : Bool
}

///|
extend NativeState with ToJson::{to_json}

///|
async fn main {
  let runtime = @cef_store.resolve_default()
  @env.set_env_var("PROTON_RUNTIME_ROOT", runtime.runtime_root())
  @proton.html(
    "Proton Occlusion Regression",
    (
      #|<!doctype html><html><head><style>
      #|html,body{margin:0;height:100%;background:#172554;color:white;font:24px system-ui}
      #|#marker{position:absolute;inset:25%;background:rgb(255,0,0)}
      #|</style></head><body><h1>Native occlusion capture</h1><div id="marker"></div>
      #|<script>
      #|window.framesSeen=0;
      #|function frame(){framesSeen++;requestAnimationFrame(frame)}requestAnimationFrame(frame);
      #|window.paintMarker=color=>{marker.style.backgroundColor=color;return true};
      #|window.readState=()=>({frames:framesSeen,visibility:document.visibilityState,focused:document.hasFocus()});
      #|</script></body></html>
    ),
    width=760,
    height=560,
    debug=true,
  )
  ..identifier("dev.proton.repro-occlusion")
  ..macos_render_when_occluded(enabled=!@env.args().contains("--default"))
  ..setup_window(context => {
    let window = context.handle()
    window.set_position(60, 90)
    let command_file = @env.get_env_var("PROTON_OCCLUSION_COMMAND").unwrap()
    context
    .task_group()
    .spawn_bg(() => {
      let mut previous = ""
      while true {
        let command = @fs.read_text(command_file)
        if command != previous {
          previous = command
          match command {
            "minimize" => window.minimize()
            "restore" => window.restore()
            "hide" => window.hide()
            "show" => window.show()
            _ => ()
          }
        }
        let state : NativeState = {
          command: previous,
          minimized: window.is_minimized(),
          visible: window.is_visible(),
        }
        @fs.write_text(command_file + ".state", state.to_json().stringify())
        @async.sleep(100)
      }
    })
  })
  .run_or_abort()
}
