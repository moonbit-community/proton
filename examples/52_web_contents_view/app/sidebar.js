const status = document.querySelector("#status");
const urlInput = document.querySelector("#url");

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
