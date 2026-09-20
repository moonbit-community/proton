///|
extern "js" fn render_bridge_status() -> Unit =
  #|() => {
  #|  const status = document.querySelector("#bridge-status");
  #|  function render() {
  #|    const ticker = window.__MoonBit__?.ticker;
  #|    if (typeof ticker?.start === "function" && typeof ticker?.on === "function") {
  #|      status.textContent = "Proton extension bridge injected.";
  #|      status.dataset.ready = "true";
  #|      return;
  #|    }
  #|    status.textContent = "Waiting for Proton extension bridge...";
  #|    status.dataset.ready = "false";
  #|    window.setTimeout(render, 100);
  #|  }
  #|  status.dataset.frontend = "warren";
  #|  render();
  #|}

///|
fn main {
  render_bridge_status()
}
