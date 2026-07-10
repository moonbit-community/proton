import "./style.css";

const status = document.querySelector("#bridge-status");

function renderBridgeStatus() {
  const ticker = window.__MoonBit__?.ticker;
  if (typeof ticker?.start === "function" && typeof ticker?.on === "function") {
    status.textContent = "Proton extension bridge injected.";
    status.dataset.ready = "true";
    return;
  }
  status.textContent = "Waiting for Proton extension bridge...";
  status.dataset.ready = "false";
  window.setTimeout(renderBridgeStatus, 100);
}

renderBridgeStatus();
