///|
fn moonbit_api_ready(ext_name : String, api : String) -> String {
  "Boolean(window.__MoonBit__ && window.__MoonBit__." +
  ext_name +
  " && window.__MoonBit__." +
  ext_name +
  "." +
  api +
  ")"
}

///|
fn scenario_ready_expression(name : String) -> String {
  match name {
    "01_tauri_like_helloworld" => "typeof window.greet === 'function'"
    "04_user_agent" => "Boolean(document.querySelector('.ua')?.textContent)"
    "06_onload" =>
      "document.body && document.body.textContent.includes('Hello, Moonbit!')"
    "07_inject_js" => "window.foo === 'bar'"
    "08_eval" =>
      "document.body && document.body.textContent.includes('Hello from Moonbit!')"
    "10_bind" => "typeof window.press === 'function'"
    "17_extension" => moonbit_api_ready("math", "sum")
    "18_extension_fs" => moonbit_api_ready("fs", "writeFile")
    "19_app_fs" =>
      "Boolean(window.__MoonBit__ && window.__MoonBit__.fs && window.__MoonBit__.path)"
    "20_app_desktop" =>
      "Boolean(window.__MoonBit__ && window.__MoonBit__.dialog && window.__MoonBit__.clipboard)"
    "21_app_shell" => moonbit_api_ready("shell", "open")
    "22_app_config" =>
      "Boolean(window.__MoonBit__ && window.__MoonBit__.fs && window.__MoonBit__.path)"
    "23_ops_runtime" =>
      "Boolean(window.__MoonBit__ && window.__MoonBit__.core && window.__MoonBit__.fs && window.__MoonBit__.path)"
    "25_app_system" =>
      "Boolean(window.__MoonBit__ && window.__MoonBit__.notification && window.__MoonBit__.tray && window.__MoonBit__.globalHotkey)"
    "26_app_path" => moonbit_api_ready("path", "basename")
    "27_app_notification" => moonbit_api_ready("notification", "show")
    "28_app_tray" => moonbit_api_ready("tray", "show")
    "29_app_global_hotkey" => moonbit_api_ready("globalHotkey", "list")
    "33_app_auto_launch" => moonbit_api_ready("autoLaunch", "support")
    "34_app_keepawake" => moonbit_api_ready("keepAwake", "status")
    "35_app_microphone" => moonbit_api_ready("microphone", "config")
    "38_async_extension_add" =>
      "Boolean(window.__MoonBit__ && window.__MoonBit__.add && window.__MoonBit__.add.slowAdd)"
    "39_sync_async_extensions" =>
      "Boolean(window.__MoonBit__ && window.__MoonBit__.math && window.__MoonBit__.add)"
    "40_event_broadcast" =>
      "Boolean(window.__MoonBit__ && window.__MoonBit__.ticker && window.__MoonBit__.ticker.start)"
    "41_app_commands" =>
      "Boolean(window.__MoonBit__ && window.__MoonBit__.core && window.__MoonBit__.core.invokeOp)"
    "42_attribute_codegen_commands" => moonbit_api_ready("add", "slowAdd")
    _ => "document.readyState !== 'loading'"
  }
}
