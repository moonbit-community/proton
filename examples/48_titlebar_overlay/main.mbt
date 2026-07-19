///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html lang="zh-CN">
    #|<head>
    #|  <meta charset="utf-8">
    #|  <meta name="viewport" content="width=device-width, initial-scale=1">
    #|  <title>Proton Overlay</title>
    #|  <script>
    #|    document.documentElement.classList.add(navigator.userAgent.includes('Windows') ? 'is-windows' : 'is-other');
    #|  </script>
    #|  <style>
    #|    :root {
    #|      color-scheme: dark;
    #|      font-family: "Segoe UI", -apple-system, sans-serif;
    #|      --leading-controls-reserve: 96px;
    #|    }
    #|    :root.is-windows { --leading-controls-reserve: 56px; }
    #|    * { box-sizing: border-box; }
    #|    html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; }
    #|    body { color: #cccccc; background: #181818; }
    #|    button, input { font: inherit; }
    #|    .titlebar {
    #|      height: 40px;
    #|      display: flex;
    #|      align-items: center;
    #|      gap: 6px;
    #|      padding: 4px 150px 4px var(--leading-controls-reserve);
    #|      color: #c7c7c7;
    #|      background: #000;
    #|      border-bottom: 1px solid #242424;
    #|      user-select: none;
    #|    }
    #|    .brand {
    #|      width: 22px;
    #|      height: 22px;
    #|      display: grid;
    #|      flex: 0 0 22px;
    #|      place-items: center;
    #|      border-radius: 5px;
    #|      color: #08111b;
    #|      background: #35a8ff;
    #|      font-size: 12px;
    #|      font-weight: 700;
    #|    }
    #|    .menu, .history, .actions { display: flex; align-items: center; gap: 2px; }
    #|    .titlebar button {
    #|      height: 28px;
    #|      border: 0;
    #|      border-radius: 5px;
    #|      color: inherit;
    #|      background: transparent;
    #|      cursor: pointer;
    #|      -webkit-app-region: no-drag;
    #|    }
    #|    .menu button { padding: 0 8px; font-size: 13px; }
    #|    .history button, .actions button { width: 28px; padding: 0; font-size: 17px; }
    #|    .titlebar button:hover { color: #fff; background: #363636; }
    #|    .command { min-width: 150px; max-width: 420px; flex: 1; margin: 0 8px; }
    #|    .command input {
    #|      width: 100%;
    #|      height: 28px;
    #|      border: 1px solid #555;
    #|      border-radius: 6px;
    #|      outline: 0;
    #|      color: #ddd;
    #|      background: #2a2a2a;
    #|      padding: 0 12px;
    #|      text-align: center;
    #|      -webkit-app-region: no-drag;
    #|    }
    #|    .command input:focus { border-color: #6a9fd3; box-shadow: 0 0 0 1px #6a9fd3; }
    #|    .actions { margin-left: auto; }
    #|    main {
    #|      height: calc(100% - 40px);
    #|      display: grid;
    #|      place-items: center;
    #|      padding: 48px 32px 64px;
    #|      text-align: center;
    #|    }
    #|    .card { width: min(650px, 100%); }
    #|    .eyebrow { color: #7aa2d6; font-size: 12px; letter-spacing: .12em; }
    #|    h1 { margin: 12px 0; color: #f0f0f0; font-size: 34px; letter-spacing: -.03em; }
    #|    p { margin: 0 auto; color: #aaa; font-size: 14px; line-height: 1.7; }
    #|    output {
    #|      display: block;
    #|      margin-top: 24px;
    #|      border-left: 2px solid #2f81f7;
    #|      background: #202020;
    #|      color: #b8d7f5;
    #|      padding: 12px 14px;
    #|      font-family: Consolas, monospace;
    #|      font-size: 12px;
    #|      text-align: left;
    #|    }
    #|    @media (max-width: 760px) {
    #|      .titlebar { padding-right: 138px; }
    #|      .menu button:nth-child(n + 3), .actions { display: none; }
    #|    }
    #|  </style>
    #|</head>
    #|<body>
    #|  <header class="titlebar">
    #|    <span class="brand" title="Web-rendered application icon">P</span>
    #|    <nav class="menu" aria-label="Application menu">
    #|      <button type="button" data-action="File menu">File</button>
    #|      <button type="button" data-action="Edit menu">Edit</button>
    #|      <button type="button" data-action="View menu">View</button>
    #|      <button type="button" data-action="Run menu">Run</button>
    #|    </nav>
    #|    <div class="history" aria-label="Navigation">
    #|      <button type="button" data-action="Back">&#8592;</button>
    #|      <button type="button" data-action="Forward">&#8594;</button>
    #|    </div>
    #|    <label class="command">
    #|      <input id="command" value="moonbit-webview" aria-label="Command center">
    #|    </label>
    #|    <div class="actions" aria-label="Layout actions">
    #|      <button type="button" data-action="Layout">&#9638;</button>
    #|      <button type="button" data-action="Panel">&#9645;</button>
    #|    </div>
    #|  </header>
    #|  <main>
    #|    <div class="card">
    #|      <div class="eyebrow">PROTON TITLEBAR OVERLAY</div>
    #|      <h1>网页组件已进入原生标题栏</h1>
    #|      <p>拖动标题栏空白区域，或双击空白区域最大化/恢复；按钮和输入框保持网页交互。Windows 右侧窗口按钮仍由系统绘制，macOS 保留左侧 traffic-light 控件。</p>
    #|      <output id="log">请点击标题栏按钮或编辑中间输入框。</output>
    #|    </div>
    #|  </main>
    #|  <script>
    #|    // Assign after DOM creation so CEF emits the initial region update.
    #|    document.querySelector('.titlebar').style.webkitAppRegion = 'drag';
    #|    const log = document.querySelector('#log');
    #|    document.querySelectorAll('[data-action]').forEach((button) => {
    #|      button.addEventListener('click', () => { log.textContent = button.dataset.action + ' received a web click.'; });
    #|    });
    #|    document.querySelector('#command').addEventListener('input', (event) => {
    #|      log.textContent = 'Command input: ' + (event.target.value || '(empty)');
    #|    });
    #|  </script>
    #|</body>
    #|</html>
  @proton.html("Proton Overlay", html, width=1000, height=640, debug=true)
  .titlebar_style(@proton.TitlebarStyle::Overlay)
  .run_or_abort()
}
