self.addEventListener("message", (event) => {
  self.postMessage(`worker:${String(event.data)}`);
});
