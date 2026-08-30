const status = document.querySelector("#status");
const urlInput = document.querySelector("#url");
const audioState = { host: false, view: false };
let hostAudioContext;
let hostOscillator;

async function navigate(url) {
  const reply = await window.__MoonBit__.browser.navigate({ url });
  status.textContent = reply.ok ? reply.url : "failed: " + reply.url;
}

document.querySelector("#go").onclick = () => {
  if (urlInput.value.trim() !== "") navigate(urlInput.value.trim());
};

urlInput.onkeydown = (event) => {
  if (event.key === "Enter") document.querySelector("#go").click();
};

for (const button of document.querySelectorAll("button[data-url]")) {
  button.onclick = () => navigate(button.dataset.url);
}

document.querySelector("#back").onclick = () =>
  window.__MoonBit__.browser.back();
document.querySelector("#forward").onclick = () =>
  window.__MoonBit__.browser.forward();
document.querySelector("#reload").onclick = () =>
  window.__MoonBit__.browser.reload();

document.querySelector("#zoom").onchange = async (event) => {
  const percent = Number(event.target.value);
  const reply = await window.__MoonBit__.browser.zoom({ percent });
  status.textContent = reply.ok ? `Zoom ${reply.percent}%` : "zoom failed";
};

document.querySelector("#host-tone").onclick = () => {
  if (!hostAudioContext) {
    hostAudioContext = new AudioContext();
    hostOscillator = hostAudioContext.createOscillator();
    hostOscillator.frequency.value = 392;
    hostOscillator.connect(hostAudioContext.destination);
    hostOscillator.start();
  }
  hostAudioContext.resume();
  status.textContent = "Host tone started";
};

async function toggleAudio(target, button) {
  const reply = await window.__MoonBit__.browser.audio({
    target,
    muted: !audioState[target],
  });
  if (!reply.ok) {
    status.textContent = `${target} audio update failed`;
    return;
  }
  audioState[target] = reply.muted;
  button.dataset.muted = String(reply.muted);
  button.textContent = `${reply.muted ? "Unmute" : "Mute"} ${
    target === "host" ? "host browser" : "web contents view"
  }`;
  status.textContent = `${target} audio muted: ${reply.muted}`;
}

document.querySelector("#host-mute").onclick = (event) =>
  toggleAudio("host", event.currentTarget);
document.querySelector("#view-mute").onclick = (event) =>
  toggleAudio("view", event.currentTarget);
