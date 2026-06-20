///|
fn command_probe_expression(name : String) -> String? {
  match name {
    "37_cef_mvp" =>
      Some("document.body.textContent.includes('CEF backend is active')")
    "38_async_extension_add" =>
      Some(
        (
          #|;(async () => {
          #|  const reply = await window.__MoonBit__.add.slowAdd({ left: 8, right: 5, delay_ms: 20 });
          #|  return reply === 13;
          #|})()
        ),
      )
    "39_sync_async_extensions" =>
      Some(
        (
          #|;(async () => {
          #|  const doubled = await window.__MoonBit__.math.double({ value: 7 });
          #|  const sum = await window.__MoonBit__.add.slowAdd({ left: 4, right: 6, delay_ms: 20 });
          #|  return doubled && doubled.doubled === 14 && sum && sum.total === 10;
          #|})()
        ),
      )
    "40_event_broadcast" =>
      Some(
        (
          #|;(async () => {
          #|  const events = [];
          #|  window.__MoonBit__.ticker.on("tick", (event) => events.push(event));
          #|  const result = await window.__MoonBit__.ticker.start({ run_id: 77, count: 2, interval_ms: 20 });
          #|  return result && result.done && result.done.total === 2 && events.length >= 1;
          #|})()
        ),
      )
    "41_app_commands" =>
      Some(
        (
          #|;(async () => {
          #|  const core = window.__MoonBit__.core;
          #|  const ping = await core.invokeOp("ext:app/ping", { name: "cdp" });
          #|  const sum = await core.invokeOp("ext:app/slowAdd", { left: 4, right: 5, delay_ms: 20 });
          #|  const report = await core.invokeOp("ext:app/reportProbe", {
          #|    report: JSON.stringify({ source: "cdp", ping, sum })
          #|  });
          #|  return sum && sum.total === 9 && report && report.ok === true;
          #|})()
        ),
      )
    "42_attribute_codegen_commands" =>
      Some(
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
        ),
      )
    _ => None
  }
}
