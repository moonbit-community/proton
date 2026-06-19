///|
fn app_probe_expression(name : String) -> String? {
  match name {
    "19_app_fs" =>
      Some(
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
        ),
      )
    "20_app_desktop" =>
      Some(
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
        ),
      )
    "21_app_shell" =>
      Some(
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
        ),
      )
    "22_app_config" =>
      Some(
        (
          #|;(async () => {
          #|  const app = window.__MoonBit__;
          #|  const joined = await app.path.join(".", "lepus-cdp-e2e-22.txt");
          #|  await app.fs.writeFile(joined, "config");
          #|  const loaded = await app.fs.readFile(joined);
          #|  await app.fs.unlink(joined).catch(() => {});
          #|  return loaded && loaded.content === "config";
          #|})()
        ),
      )
    "23_ops_runtime" =>
      Some(
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
        ),
      )
    "24_app_multi_window" => Some("document.readyState !== 'loading'")
    "25_app_system" =>
      Some(
        (
          #|;(async () => {
          #|  const app = window.__MoonBit__;
          #|  const shortcuts = await app.globalHotkey.list({});
          #|  return typeof app.notification.show === "function" &&
          #|    typeof app.tray.show === "function" &&
          #|    shortcuts &&
          #|    Array.isArray(shortcuts.accelerators);
          #|})()
        ),
      )
    "26_app_path" =>
      Some(
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
        ),
      )
    "27_app_notification" =>
      Some("typeof window.__MoonBit__.notification.show === 'function'")
    "28_app_tray" =>
      Some(
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
          #|    const message = String(error);
          #|    return message.toLowerCase().includes("tray") ||
          #|      message.includes("Shell_NotifyIconW");
          #|  }
          #|})()
        ),
      )
    "29_app_global_hotkey" =>
      Some(
        (
          #|;(async () => {
          #|  const reply = await window.__MoonBit__.globalHotkey.list({});
          #|  return reply && Array.isArray(reply.accelerators);
          #|})()
        ),
      )
    "33_app_auto_launch" =>
      Some(
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
        ),
      )
    "34_app_keepawake" =>
      Some(
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
        ),
      )
    "35_app_microphone" =>
      Some(
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
        ),
      )
    _ => None
  }
}
