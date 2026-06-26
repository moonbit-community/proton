///|
fn scenario_probe_expression(name : String) -> String {
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
        #|    if (!String(error && error.message ? error.message : error).includes("Failure crossed command boundary")) return false;
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
    _ => "document.readyState !== 'loading'"
  }
}
