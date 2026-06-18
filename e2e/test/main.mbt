///|
fn env_or(name : String, default : String) -> String {
  match @env.get_env_var(name) {
    Some(value) if value != "" => value
    _ => default
  }
}

///|
fn cdp_target() -> @client.CdpTarget raise {
  @client.parse_cdp_target(env_or("MBT_CDP_TARGET", "9222"))
}

///|
fn cdp_http_endpoint() -> String {
  let target = env_or("MBT_CDP_TARGET", "9222")
  if target.has_prefix("http://") || target.has_prefix("https://") {
    target
  } else if target.has_prefix("ws://") || target.has_prefix("wss://") {
    target
  } else if target.contains(":") {
    "http://" + target
  } else {
    "http://127.0.0.1:" + target
  }
}

///|
fn scenario_name() -> String {
  env_or("MBT_LEPUS_E2E_SCENARIO", "38_async_extension_add")
}

///|
fn timeout_ms() -> Int {
  match @env.get_env_var("MBT_LEPUS_E2E_TIMEOUT_MS") {
    Some(value) =>
      try @string.parse_int(value) catch {
        _ => 30000
      } noraise {
        parsed => parsed
      }
    None => 30000
  }
}

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

///|
fn scenario_probe_expression(name : String) -> String {
  match name {
    "01_tauri_like_helloworld" =>
      (
        #|;(async () => {
        #|  const reply = await window.greet("CDP");
        #|  return reply && reply.message === "Hello CDP, You have been greeted from Moonbit!";
        #|})()
      )
    "02_local" => "document.body.textContent.includes('Hello, Moonbit!')"
    "04_user_agent" =>
      "document.querySelector('.ua').textContent === window.navigator.userAgent && window.navigator.userAgent.length > 0"
    "05_alert" => "document.body.textContent.includes('Alert demo is running')"
    "06_onload" => "document.body.textContent.includes('Hello, Moonbit!')"
    "07_inject_js" =>
      "window.foo === 'bar' && document.body.textContent.trim() === 'bar'"
    "08_eval" => "document.body.textContent.includes('Hello from Moonbit!')"
    "10_bind" =>
      (
        #|;(async () => {
        #|  const reply = await window.press("cdp", 7, "probe");
        #|  return reply &&
        #|    reply.message === "Handled by MoonBit" &&
        #|    reply.count >= 1 &&
        #|    reply.args[0] === "cdp" &&
        #|    reply.args[1] === 7;
        #|})()
      )
    "11_multi_window" => "document.readyState !== 'loading'"
    "12_embed" => "document.body.textContent.includes('Hello, Moonbit!')"
    "14_beforeunload" => "document.body.textContent.includes('Hello, Moonbit!')"
    "15_close" =>
      "Boolean(document.querySelector('button')) && document.body.textContent.includes('Close Webview')"
    "17_extension" =>
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
      )
    "18_extension_fs" =>
      (
        #|;(async () => {
        #|  const fs = window.__MoonBit__.fs;
        #|  const path = "lepus-cdp-e2e-18.txt";
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
      )
    "19_app_fs" =>
      (
        #|;(async () => {
        #|  const fs = window.__MoonBit__.fs;
        #|  const path = "lepus-cdp-e2e.txt";
        #|  await fs.writeFile(path, "hello");
        #|  await fs.appendFile(path, " cdp");
        #|  const loaded = await fs.readFile(path);
        #|  await fs.unlink(path).catch(() => {});
        #|  return loaded && loaded.content === "hello cdp";
        #|})()
      )
    "20_app_desktop" =>
      (
        #|;(async () => {
        #|  const app = window.__MoonBit__;
        #|  let previous = null;
        #|  try {
        #|    previous = await app.clipboard.readText({});
        #|  } catch (_) {}
        #|  const text = "lepus-cdp-clipboard-" + Date.now();
        #|  const events = [];
        #|  app.events.on("clipboard.activity", (event) => events.push(event));
        #|  try {
        #|    const written = await app.clipboard.writeText({ text });
        #|    const loaded = await app.clipboard.readText({});
        #|    return typeof app.dialog.message === "function" &&
        #|      written &&
        #|      written.written === true &&
        #|      loaded &&
        #|      loaded.text === text &&
        #|      events.length >= 1;
        #|  } finally {
        #|    if (previous && typeof previous.text === "string") {
        #|      await app.clipboard.writeText({ text: previous.text }).catch(() => {});
        #|    }
        #|  }
        #|})()
      )
    "21_app_shell" =>
      (
        #|;(async () => {
        #|  const shell = window.__MoonBit__.shell;
        #|  if (typeof shell.open !== "function" || typeof shell.revealItem !== "function") {
        #|    return false;
        #|  }
        #|  try {
        #|    await shell.open({ target: "" });
        #|    return false;
        #|  } catch (error) {
        #|    return String(error).includes("must not be empty");
        #|  }
        #|})()
      )
    "22_app_config" =>
      (
        #|;(async () => {
        #|  const app = window.__MoonBit__;
        #|  const joined = await app.path.join(".", "lepus-cdp-e2e-22.txt");
        #|  await app.fs.writeFile(joined, "config");
        #|  const loaded = await app.fs.readFile(joined);
        #|  await app.fs.unlink(joined).catch(() => {});
        #|  return loaded && loaded.content === "config";
        #|})()
      )
    "23_ops_runtime" =>
      (
        #|;(async () => {
        #|  const app = window.__MoonBit__;
        #|  const resolved = await app.core.invokeOp("ext:path/resolve", { path: "." });
        #|  const dirname = await app.path.dirname(resolved.path);
        #|  const listed = await app.fs.readdir(".");
        #|  return app.core.hasOp("ext:path/resolve") &&
        #|    resolved &&
        #|    typeof resolved.path === "string" &&
        #|    typeof dirname === "string" &&
        #|    listed &&
        #|    Array.isArray(listed.entries);
        #|})()
      )
    "24_app_multi_window" => "document.readyState !== 'loading'"
    "25_app_system" =>
      (
        #|;(async () => {
        #|  const app = window.__MoonBit__;
        #|  const shortcuts = await app.globalHotkey.list({});
        #|  return typeof app.notification.show === "function" &&
        #|    typeof app.tray.show === "function" &&
        #|    shortcuts &&
        #|    Array.isArray(shortcuts.accelerators);
        #|})()
      )
    "26_app_path" =>
      (
        #|;(async () => {
        #|  const path = window.__MoonBit__.path;
        #|  const basename = await path.basename("fixtures/demo.html", ".html");
        #|  const dirname = await path.dirname("fixtures/demo.html");
        #|  const joined = await path.join("fixtures", "child", "index.html");
        #|  const parsed = await path.parse("fixtures/demo.html");
        #|  return basename === "demo" &&
        #|    typeof dirname === "string" &&
        #|    joined.includes("child") &&
        #|    parsed &&
        #|    parsed.name === "demo";
        #|})()
      )
    "27_app_notification" =>
      "typeof window.__MoonBit__.notification.show === 'function'"
    "28_app_tray" =>
      (
        #|;(async () => {
        #|  const tray = window.__MoonBit__.tray;
        #|  try {
        #|    const shown = await tray.show({ tooltip: "Lepus CDP e2e" });
        #|    const hidden = await tray.hide({});
        #|    return shown &&
        #|      hidden &&
        #|      typeof shown.visible === "boolean" &&
        #|      typeof hidden.visible === "boolean";
        #|  } catch (error) {
        #|    return String(error).includes("tray");
        #|  }
        #|})()
      )
    "29_app_global_hotkey" =>
      (
        #|;(async () => {
        #|  const reply = await window.__MoonBit__.globalHotkey.list({});
        #|  return reply && Array.isArray(reply.accelerators);
        #|})()
      )
    "33_app_auto_launch" =>
      (
        #|;(async () => {
        #|  const api = window.__MoonBit__.autoLaunch;
        #|  const support = await api.support({});
        #|  const described = await api.describe({
        #|    name: "LepusCdpE2E",
        #|    identifier: "justjavac.lepus.cdp.e2e"
        #|  });
        #|  return support &&
        #|    typeof support.supported === "boolean" &&
        #|    typeof support.platform === "string" &&
        #|    described &&
        #|    described.name === "LepusCdpE2E";
        #|})()
      )
    "34_app_keepawake" =>
      (
        #|;(async () => {
        #|  const api = window.__MoonBit__.keepAwake;
        #|  const before = await api.status({});
        #|  const acquired = await api.acquire({ reason: "Lepus CDP e2e", scope: "system" });
        #|  const during = await api.status({});
        #|  const released = await api.release({});
        #|  return before &&
        #|    acquired &&
        #|    during &&
        #|    released &&
        #|    acquired.active === true &&
        #|    during.active === true &&
        #|    released.active === false;
        #|})()
      )
    "35_app_microphone" =>
      (
        #|;(async () => {
        #|  const api = window.__MoonBit__.microphone;
        #|  const config = await api.config({
        #|    channels: 2,
        #|    sample_rate_hz: 44100,
        #|    sample_format: "f32",
        #|    echo_cancellation: true,
        #|    noise_suppression: true
        #|  });
        #|  const parsed = await api.parseListing({ listing: "" });
        #|  return config &&
        #|    config.channels === 2 &&
        #|    config.sample_rate_hz === 44100 &&
        #|    config.sample_format === "f32" &&
        #|    Array.isArray(parsed.devices);
        #|})()
      )
    "37_cef_mvp" =>
      "document.body.textContent.includes('CEF backend is active')"
    "38_async_extension_add" =>
      (
        #|;(async () => {
        #|  const reply = await window.__MoonBit__.add.slowAdd({ left: 8, right: 5, delay_ms: 20 });
        #|  return reply === 13;
        #|})()
      )
    "39_sync_async_extensions" =>
      (
        #|;(async () => {
        #|  const doubled = await window.__MoonBit__.math.double({ value: 7 });
        #|  const sum = await window.__MoonBit__.add.slowAdd({ left: 4, right: 6, delay_ms: 20 });
        #|  return doubled && doubled.doubled === 14 && sum && sum.total === 10;
        #|})()
      )
    "40_event_broadcast" =>
      (
        #|;(async () => {
        #|  const events = [];
        #|  window.__MoonBit__.ticker.on("tick", (event) => events.push(event));
        #|  const result = await window.__MoonBit__.ticker.start({ run_id: 77, count: 2, interval_ms: 20 });
        #|  return result && result.done && result.done.total === 2 && events.length >= 1;
        #|})()
      )
    "41_app_commands" =>
      (
        #|;(async () => {
        #|  const core = window.__MoonBit__.core;
        #|  const ping = await core.invokeOp("app:ping", { name: "cdp" });
        #|  const sum = await core.invokeOp("app:slowAdd", { left: 4, right: 5, delay_ms: 20 });
        #|  const report = await core.invokeOp("app:reportProbe", {
        #|    report: JSON.stringify({ source: "cdp", ping, sum })
        #|  });
        #|  return sum && sum.total === 9 && report && report.ok === true;
        #|})()
      )
    "42_attribute_codegen_commands" =>
      (
        #|;(async () => {
        #|  const events = [];
        #|  window.__MoonBit__.events.on("add.addFinished", (event) => events.push(event));
        #|  const reply = await window.__MoonBit__.add.slowAdd({ left: 11, right: 12, delay_ms: 20 });
        #|  return reply &&
        #|    reply.total === 23 &&
        #|    reply.waited_ms === 20 &&
        #|    events.some((event) => event.payload && event.payload.total === 23);
        #|})()
      )
    _ => "document.readyState !== 'loading'"
  }
}

///|
async fn evaluate_bool(
  page : @client.CdpClient,
  expression : String,
  await_promise : Bool,
) -> Bool {
  let response = page.send_schema_command("Runtime.evaluate", params={
    "expression": expression,
    "returnByValue": true,
    "awaitPromise": await_promise,
  })
  match @client.cdp_response_result_json(response) {
    { "result": { "value": true, .. }, .. } => true
    _ => false
  }
}

///|
async fn wait_for_ready(
  page : @client.CdpClient,
  expression : String,
  timeout : Int,
) -> Unit {
  let attempts = timeout / 100
  for attempt in 0..<=attempts {
    if evaluate_bool(page, expression, false) {
      return
    }
    if attempt < attempts {
      @async.sleep(100)
    }
  }
  fail("CDP e2e timed out waiting for ready expression: " + expression)
}

///|
async fn main {
  let name = scenario_name()
  ignore(
    @client.wait_for_browser_endpoint(
      cdp_http_endpoint(),
      timeout_ms=timeout_ms(),
    ),
  )
  let page = @client.connect_cdp_page_target_with_timeout(
    cdp_target(),
    timeout_ms=timeout_ms(),
  )
  defer page.close()
  ignore(page.send_schema_command("Runtime.enable"))
  wait_for_ready(page, scenario_ready_expression(name), timeout_ms())
  guard evaluate_bool(page, scenario_probe_expression(name), true) else {
    fail("CDP e2e probe failed for " + name)
  }
  println("CDP e2e passed: " + name)
}
