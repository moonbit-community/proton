///|
fn basic_probe_expression(name : String) -> String? {
  match name {
    "01_tauri_like_helloworld" =>
      Some(
        (
          #|;(async () => {
          #|  const reply = await window.greet("CDP");
          #|  return reply && reply.message === "Hello CDP, You have been greeted from Moonbit!";
          #|})()
        ),
      )
    "02_local" => Some("document.body.textContent.includes('Hello, Moonbit!')")
    "04_user_agent" =>
      Some(
        "document.querySelector('.ua').textContent === window.navigator.userAgent && window.navigator.userAgent.length > 0",
      )
    "05_alert" =>
      Some("document.body.textContent.includes('Alert demo is running')")
    "06_onload" => Some("document.body.textContent.includes('Hello, Moonbit!')")
    "07_inject_js" =>
      Some("window.foo === 'bar' && document.body.textContent.trim() === 'bar'")
    "08_eval" =>
      Some("document.body.textContent.includes('Hello from Moonbit!')")
    "10_bind" =>
      Some(
        (
          #|;(async () => {
          #|  const reply = await window.press("cdp", 7, "probe");
          #|  return reply &&
          #|    reply.message === "Handled by MoonBit" &&
          #|    reply.count >= 1 &&
          #|    reply.args[0] === "cdp" &&
          #|    reply.args[1] === 7;
          #|})()
        ),
      )
    "11_multi_window" => Some("document.readyState !== 'loading'")
    "12_embed" => Some("document.body.textContent.includes('Hello, Moonbit!')")
    "14_beforeunload" =>
      Some("document.body.textContent.includes('Hello, Moonbit!')")
    "15_close" =>
      Some(
        "Boolean(document.querySelector('button')) && document.body.textContent.includes('Close Webview')",
      )
    "17_extension" =>
      Some(
        (
          #|;(async () => {
          #|  const events = [];
          #|  window.__MoonBit__.events.on("math.computed", (event) => events.push(event));
          #|  const direct = await window.__MoonBit__.core.invokeOp("ext:math/sum", { left: 10, right: 20 });
          #|  const helper = await window.__MoonBit__.math.sum({ left: 5, right: 7 });
          #|  return direct && helper &&
          #|    direct.total === 30 &&
          #|    helper.total === 12 &&
          #|    events.length >= 2 &&
          #|    events.every((event) => event.extension === "math" && event.name === "computed");
          #|})()
        ),
      )
    "18_extension_fs" =>
      Some(
        (
          #|;(async () => {
          #|  const fs = window.__MoonBit__.fs;
          #|  const path = "proton-cdp-e2e-18.txt";
          #|  await fs.writeFile(path, "hello");
          #|  await fs.appendFile(path, " fs");
          #|  const loaded = await fs.readFile(path);
          #|  const exists = await fs.exists(path);
          #|  await fs.unlink(path).catch(() => {});
          #|  return loaded &&
          #|    loaded.content === "hello fs" &&
          #|    exists &&
          #|    exists.exists === true;
          #|})()
        ),
      )
    _ => None
  }
}
