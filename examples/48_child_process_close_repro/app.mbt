///|
let resource : String =
  #|<!doctype html>
  #|<html>
  #|  <head>
  #|    <meta charset="utf-8" />
  #|    <title>Child Process Close Repro</title>
  #|    <style>
  #|      :root {
  #|        color-scheme: light dark;
  #|        font-family: system-ui, sans-serif;
  #|      }
  #|
  #|      body {
  #|        margin: 0;
  #|        padding: 28px;
  #|      }
  #|
  #|      main {
  #|        max-width: 620px;
  #|        display: grid;
  #|        gap: 14px;
  #|      }
  #|
  #|      h1 {
  #|        margin: 0;
  #|        font-size: 28px;
  #|      }
  #|
  #|      output,
  #|      pre {
  #|        font: 13px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace;
  #|      }
  #|
  #|      pre {
  #|        min-height: 180px;
  #|        margin: 0;
  #|        padding: 14px;
  #|        border: 1px solid color-mix(in srgb, currentColor 24%, transparent);
  #|        border-radius: 6px;
  #|        overflow: auto;
  #|      }
  #|    </style>
  #|  </head>
  #|  <body>
  #|    <main>
  #|      <h1>Child Process Close Repro</h1>
  #|      <output id="status">starting bridge request...</output>
  #|      <pre id="log"></pre>
  #|    </main>
  #|    <script>
  #|      const status = document.getElementById("status");
  #|      const log = document.getElementById("log");
  #|
  #|      function append(message) {
  #|        log.textContent += `${new Date().toISOString()} ${message}\n`;
  #|      }
  #|
  #|      async function waitForBridge() {
  #|        for (let attempt = 0; attempt < 80; attempt += 1) {
  #|          if (window.__MoonBit__?.core?.invokeOp) {
  #|            return window.__MoonBit__.core.invokeOp;
  #|          }
  #|          await new Promise(resolve => setTimeout(resolve, 25));
  #|        }
  #|        throw new Error("bridge is not available");
  #|      }
  #|
  #|      async function startHold() {
  #|        append("waiting for window.__MoonBit__.core.invokeOp");
  #|        const invokeOp = await waitForBridge();
  #|        append('calling core.invokeOp("ext:child/hold")');
  #|        status.textContent = "bridge request pending with child process";
  #|        invokeOp("ext:child/hold", {}).then(
  #|          value => {
  #|            status.textContent = "bridge request completed";
  #|            append(`completed: ${JSON.stringify(value)}`);
  #|          },
  #|          error => {
  #|            status.textContent = "bridge request rejected";
  #|            append(`rejected: ${String(error)}`);
  #|          },
  #|        );
  #|      }
  #|
  #|      startHold().catch(error => {
  #|        status.textContent = "failed to start bridge request";
  #|        append(`failed: ${String(error)}`);
  #|      });
  #|    </script>
  #|  </body>
  #|</html>
  #|
