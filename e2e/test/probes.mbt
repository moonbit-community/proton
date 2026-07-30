///|
fn scenario_probe_expression(name : String) -> String raise {
  match name {
    "41_app_commands" =>
      (
        #|;(async () => {
        #|  const invoke = window.__MoonBit__?.core?.invokeOp;
        #|  if (location.href !== "proton://app/") return false;
        #|  if (document.title !== "MoonBit App Commands") return false;
        #|  if (typeof invoke !== "function") return false;
        #|  const ping = await invoke("ext:app/ping", { name: "proton" });
        #|  if (!ping || ping.message !== "Hello proton from the app command layer") return false;
        #|  const sum = await invoke("ext:app/slowAdd", { left: 20, right: 22, delay_ms: 50 });
        #|  if (!sum || sum.total !== 42 || sum.source !== "commands") return false;
        #|  try {
        #|    await invoke("ext:app/unknown", {});
        #|    return false;
        #|  } catch (error) {
        #|    if (!String(error && error.message ? error.message : error).includes("bridge op is not allowed")) return false;
        #|  }
        #|  try {
        #|    await invoke("ext:app/fail", { message: "Failure crossed command boundary" });
        #|    return false;
        #|  } catch (error) {
        #|    if (!String(error && error.message ? error.message : error).includes("op ext:app/fail failed")) return false;
        #|  }
        #|  try {
        #|    await invoke("ext:app/ping", { oversized: "x".repeat(1048577) });
        #|    return false;
        #|  } catch (error) {
        #|    const message = String(error && error.message ? error.message : error);
        #|    if (!message.includes("invalid bridge request") && !message.includes("bridge payload is too large")) return false;
        #|  }
        #|  return true;
        #|})()
      )
    "38_async_extension_add" =>
      (
        #|;(async () => {
        #|  if (location.href !== "proton://app/") return false;
        #|  if (document.title !== "MoonBit Async Add Extension") return false;
        #|  if (typeof window.__MoonBit__?.core?.invokeOp !== "function") return false;
        #|  if (typeof window.__MoonBit__?.add?.slowAdd !== "function") return false;
        #|  const reply = await window.__MoonBit__.add.slowAdd({ left: 2, right: 3 });
        #|  return reply === 5;
        #|})()
      )
    "39_sync_async_extensions" =>
      (
        #|;(async () => {
        #|  if (location.href !== "proton://app/") return false;
        #|  if (document.title !== "MoonBit Sync + Async Extensions") return false;
        #|  if (typeof window.__MoonBit__?.core?.invokeOp !== "function") return false;
        #|  if (typeof window.__MoonBit__?.math?.double !== "function") return false;
        #|  if (typeof window.__MoonBit__?.add?.slowAdd !== "function") return false;
        #|  const doubled = await window.__MoonBit__.math.double({ value: 21 });
        #|  const added = await window.__MoonBit__.add.slowAdd({ left: 20, right: 22, delay_ms: 10 });
        #|  return doubled?.value === 21 &&
        #|    doubled?.doubled === 42 &&
        #|    doubled?.source === "sync command extension" &&
        #|    added?.total === 42 &&
        #|    added?.waited_ms === 10 &&
        #|    added?.source === "async command extension";
        #|})()
      )
    "40_event_broadcast" =>
      (
        #|;(async () => {
        #|  if (location.href !== "proton://app/") return false;
        #|  if (document.title !== "MoonBit Event Broadcast") return false;
        #|  if (typeof window.__MoonBit__?.core?.invokeOp !== "function") return false;
        #|  if (typeof window.__MoonBit__?.ticker?.start !== "function") return false;
        #|  if (typeof window.__MoonBit__?.ticker?.on !== "function") return false;
        #|  const events = [];
        #|  window.__MoonBit__.ticker.on("tick", (event) => {
        #|    events.push({
        #|      kind: "tick",
        #|      run_id: event.payload.run_id,
        #|      index: event.payload.index,
        #|      total: event.payload.total,
        #|    });
        #|  });
        #|  window.__MoonBit__.ticker.on("done", (event) => {
        #|    events.push({
        #|      kind: "done",
        #|      run_id: event.payload.run_id,
        #|      total: event.payload.total,
        #|    });
        #|  });
        #|  const reply = await window.__MoonBit__.ticker.start({
        #|    run_id: 9001,
        #|    count: 3,
        #|    interval_ms: 100,
        #|  });
        #|  if (reply?.done?.run_id !== 9001 || reply?.done?.total !== 3) return false;
        #|  if (!Array.isArray(reply?.ticks) || reply.ticks.length !== 3) return false;
        #|  if (!reply.ticks.every((tick, index) =>
        #|    tick?.run_id === 9001 &&
        #|    tick?.index === index + 1 &&
        #|    tick?.total === 3 &&
        #|    tick?.remaining === 2 - index
        #|  )) return false;
        #|  const ticks = events.filter((event) => event.kind === "tick");
        #|  const done = events.filter((event) => event.kind === "done");
        #|  return ticks.length === 3 &&
        #|    ticks.every((event, index) =>
        #|      event.run_id === 9001 &&
        #|      event.index === index + 1 &&
        #|      event.total === 3
        #|    ) &&
        #|    done.length === 1 &&
        #|    done[0]?.run_id === 9001 &&
        #|    done[0]?.total === 3;
        #|})()
      )
    "46_asset_sidecar_resources" =>
      (
        #|;(async () => {
        #|  if (!String(location.href).startsWith("proton://app/")) return false;
        #|  if (document.title !== "Asset Sidecar Resources") return false;
        #|  if (typeof window.__MoonBit__?.core?.invokeOp !== "function") return false;
        #|  if (typeof window.__MoonBit__?.add?.add !== "function") return false;
        #|  if (typeof window.__MoonBit__?.add?.addLater !== "function") return false;
        #|  if (typeof window.__MoonBit__?.add?.reportProbe !== "function") return false;
        #|  if (document.querySelector("#log")?.textContent !== "Bridge ready.") return false;
        #|  document.querySelector("#instant-left").value = "30";
        #|  document.querySelector("#instant-right").value = "12";
        #|  document.querySelector("#instant-form").requestSubmit();
        #|  await new Promise((resolve) => setTimeout(resolve, 50));
        #|  document.querySelector("#delayed-left").value = "9";
        #|  document.querySelector("#delayed-right").value = "8";
        #|  document.querySelector("#delayed-form").requestSubmit();
        #|  await new Promise((resolve) => setTimeout(resolve, 950));
        #|  const commandReply = await window.__MoonBit__.add.add({ left: 30, right: 12 });
        #|  const delayedReply = await window.__MoonBit__.add.addLater({ left: 20, right: 22 });
        #|  await window.__MoonBit__.add.reportProbe({
        #|    report: JSON.stringify({ ok: commandReply === 42 && delayedReply === 42, source: "moonbit-driver" }),
        #|  });
        #|  const passed = document.querySelector("#instant-result")?.textContent === "42" &&
        #|    document.querySelector("#delayed-result")?.textContent === "17" &&
        #|    getComputedStyle(document.documentElement).getPropertyValue("--accent").trim() !== "" &&
        #|    Boolean(document.querySelector('script[src="app.js"]')) &&
        #|    commandReply === 42 &&
        #|    delayedReply === 42;
        #|  document.querySelector("#log").textContent = "Bridge ready.";
        #|  return passed;
        #|})()
      )
    "47_dev_extension_js" =>
      (
        #|;(async () => {
        #|  if (location.protocol !== "http:" || location.hostname !== "127.0.0.1") return false;
        #|  if (document.title !== "Proton Dev Extension JS") return false;
        #|  if (typeof window.__MoonBit__?.core?.invokeOp !== "function") return false;
        #|  if (typeof window.__MoonBit__?.ticker?.start !== "function") return false;
        #|  if (typeof window.__MoonBit__?.ticker?.on !== "function") return false;
        #|  if (document.querySelector("#bridge-status")?.dataset.ready !== "true") return false;
        #|  const protonScriptCount = Array.from(document.scripts).filter((script) => {
        #|    const text = (script.src || "") + "\n" + (script.textContent || "");
        #|    return /proton|moonbit/i.test(text);
        #|  }).length;
        #|  if (protonScriptCount !== 0) return false;
        #|  const events = [];
        #|  window.__MoonBit__.ticker.on("tick", (event) => events.push({
        #|    kind: "tick", run_id: event.payload.run_id,
        #|    index: event.payload.index, total: event.payload.total,
        #|  }));
        #|  window.__MoonBit__.ticker.on("done", (event) => events.push({
        #|    kind: "done", run_id: event.payload.run_id,
        #|    total: event.payload.total,
        #|  }));
        #|  const reply = await window.__MoonBit__.ticker.start({
        #|    run_id: 9201, count: 2, interval_ms: 50,
        #|  });
        #|  if (reply?.done?.run_id !== 9201 || reply?.done?.total !== 2) return false;
        #|  if (!Array.isArray(reply?.ticks) || reply.ticks.length !== 2) return false;
        #|  if (!reply.ticks.every((tick, index) =>
        #|    tick?.run_id === 9201 && tick?.index === index + 1 &&
        #|    tick?.total === 2 && tick?.remaining === 1 - index
        #|  )) return false;
        #|  const ticks = events.filter((event) => event.kind === "tick");
        #|  const done = events.filter((event) => event.kind === "done");
        #|  return ticks.length === 2 &&
        #|    ticks.every((event, index) =>
        #|      event.run_id === 9201 && event.index === index + 1 && event.total === 2
        #|    ) &&
        #|    done.length === 1 && done[0]?.run_id === 9201 && done[0]?.total === 2;
        #|})()
      )
    "42_attribute_codegen_commands" =>
      (
        #|;(async () => {
        #|  if (location.href !== "proton://app/") return false;
        #|  if (document.title !== "Proton Attribute Codegen") return false;
        #|  if (typeof window.__MoonBit__?.core?.invokeOp !== "function") return false;
        #|  if (typeof window.__MoonBit__?.add?.slowAdd !== "function") return false;
        #|  if (typeof window.__MoonBit__?.events?.on !== "function") return false;
        #|  const events = [];
        #|  window.__MoonBit__.events.on("add.addFinished", (event) => events.push(event));
        #|  const reply = await window.__MoonBit__.add.slowAdd({ left: 20, right: 22, delay_ms: 25 });
        #|  return reply?.total === 42 &&
        #|    reply?.waited_ms === 25 &&
        #|    events.length === 1 &&
        #|    events[0]?.name === "addFinished" &&
        #|    events[0]?.extension === "add" &&
        #|    events[0]?.payload?.total === 42;
        #|})()
      )
    _ => fail("unsupported E2E scenario: " + name)
  }
}
