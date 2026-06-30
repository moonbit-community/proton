const result = document.querySelector("#result");
const log = document.querySelector("#log");
const button = document.querySelector("#add");

function setLog(message) {
  log.textContent = message;
}

async function reportProbe(report) {
  try {
    await window.__MoonBit__.add.reportProbe({
      report: JSON.stringify(report),
    });
  } catch (error) {
    setLog(`Probe report failed: ${String(error)}`);
  }
}

async function runAdd() {
  setLog("Calling add.add from app.js...");
  try {
    const total = await window.__MoonBit__.add.add({ left: 7, right: 5 });
    result.textContent = String(total);
    setLog(`Result: ${total}`);
    await reportProbe({
      ok: total === 12,
      total,
      css_loaded:
        getComputedStyle(document.documentElement).getPropertyValue("--accent").trim() !== "",
      script_url: document.currentScript ? document.currentScript.src : "loaded",
    });
  } catch (error) {
    result.textContent = "error";
    setLog(String(error));
    await reportProbe({
      ok: false,
      error: String(error),
    });
  }
}

function waitForBridge(attempt = 0) {
  if (window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.add?.add) {
    void runAdd();
    return;
  }
  if (attempt > 80) {
    setLog("Bridge timed out.");
    void reportProbe({
      ok: false,
      stage: "bridge-timeout",
      has_moonbit: !!window.__MoonBit__,
      has_add: !!window.__MoonBit__?.add,
    });
    return;
  }
  window.setTimeout(() => waitForBridge(attempt + 1), 25);
}

button.addEventListener("click", () => void runAdd());
window.addEventListener("load", () => waitForBridge());
