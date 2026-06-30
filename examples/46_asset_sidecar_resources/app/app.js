const log = document.querySelector("#log");
const instantForm = document.querySelector("#instant-form");
const delayedForm = document.querySelector("#delayed-form");
const instantResult = document.querySelector("#instant-result");
const delayedResult = document.querySelector("#delayed-result");
const controls = document.querySelectorAll("input, button");

controls.forEach((control) => {
  control.disabled = true;
});

function setLog(message) {
  log.textContent = message;
}

function readPair(prefix) {
  const left = document.querySelector(`#${prefix}-left`).valueAsNumber;
  const right = document.querySelector(`#${prefix}-right`).valueAsNumber;
  if (!Number.isFinite(left) || !Number.isFinite(right)) {
    throw new Error("Enter two numbers.");
  }
  return { left, right };
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

async function runImmediateAdd() {
  try {
    const payload = readPair("instant");
    setLog("Calling add.add...");
    const total = await window.__MoonBit__.add.add(payload);
    instantResult.textContent = String(total);
    setLog(`Immediate result: ${total}`);
  } catch (error) {
    instantResult.textContent = "error";
    setLog(String(error));
  }
}

async function runDelayedAdd() {
  try {
    const payload = readPair("delayed");
    delayedResult.textContent = "...";
    setLog("Calling add.addLater...");
    const total = await window.__MoonBit__.add.addLater(payload);
    delayedResult.textContent = String(total);
    setLog(`Delayed result: ${total}`);
  } catch (error) {
    delayedResult.textContent = "error";
    setLog(String(error));
  }
}

async function runProbe() {
  try {
    const instantTotal = await window.__MoonBit__.add.add({ left: 7, right: 5 });
    const delayedTotal = await window.__MoonBit__.add.addLater({ left: 1, right: 2 });
    await reportProbe({
      ok: instantTotal === 12 && delayedTotal === 3,
      instant_total: instantTotal,
      delayed_total: delayedTotal,
      css_loaded:
        getComputedStyle(document.documentElement).getPropertyValue("--accent").trim() !== "",
      script_url: document.currentScript ? document.currentScript.src : "loaded",
    });
  } catch (error) {
    await reportProbe({
      ok: false,
      error: String(error),
    });
  }
}

function enableControls() {
  controls.forEach((control) => {
    control.disabled = false;
  });
}

function waitForBridge(attempt = 0) {
  const commands = window.__MoonBit__?.add;
  if (window.__MoonBit__?.core?.invokeOp && commands?.add && commands?.addLater) {
    enableControls();
    setLog("Bridge ready.");
    void runProbe();
    return;
  }
  if (attempt > 80) {
    setLog("Bridge timed out.");
    void reportProbe({
      ok: false,
      stage: "bridge-timeout",
      has_moonbit: !!window.__MoonBit__,
      has_add: !!commands,
    });
    return;
  }
  window.setTimeout(() => waitForBridge(attempt + 1), 25);
}

instantForm.addEventListener("submit", (event) => {
  event.preventDefault();
  void runImmediateAdd();
});

delayedForm.addEventListener("submit", (event) => {
  event.preventDefault();
  void runDelayedAdd();
});

window.addEventListener("load", () => waitForBridge());
