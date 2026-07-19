///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html lang="zh-CN">
    #|<head>
    #|  <meta charset="utf-8">
    #|  <meta name="viewport" content="width=device-width, initial-scale=1">
    #|  <title>Proton Overlay</title>
    #|  <style>
    #|    * { box-sizing: border-box; }
    #|    html, body { margin: 0; min-height: 100%; }
    #|    body {
    #|      color: #27292c;
    #|      background: #fff;
    #|      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
    #|    }
    #|    .titlebar {
    #|      height: 30px;
    #|      display: flex;
    #|      align-items: center;
    #|      gap: 13px;
    #|      padding: 3px 10px 3px 96px;
    #|      color: #606367;
    #|      background: #f8f8fa;
    #|      border-bottom: 1px solid #e1e2e4;
    #|    }
    #|    .history {
    #|      display: flex;
    #|      align-items: center;
    #|      gap: 12px;
    #|      height: 16px;
    #|    }
    #|    .history svg {
    #|      width: 16px;
    #|      height: 16px;
    #|      fill: none;
    #|      stroke: currentColor;
    #|      stroke-width: 1.7;
    #|      stroke-linecap: round;
    #|      stroke-linejoin: round;
    #|    }
    #|    .history .disabled { color: #b7b9bc; }
    #|    .command {
    #|      width: 190px;
    #|      height: 24px;
    #|      display: flex;
    #|      align-items: center;
    #|      overflow: hidden;
    #|      color: #5f6266;
    #|      background: #fff;
    #|      border: 1px solid #d8dadd;
    #|      border-radius: 8px;
    #|      box-shadow: 0 1px 2px rgba(0,0,0,.05);
    #|      font-size: 12px;
    #|    }
    #|    .branch { flex: 1; padding: 0 10px; white-space: nowrap; }
    #|    .count {
    #|      height: 100%;
    #|      display: flex;
    #|      align-items: center;
    #|      gap: 5px;
    #|      padding: 0 10px;
    #|      color: #202226;
    #|      background: #e7effa;
    #|      border-left: 1px solid #e0e1e3;
    #|    }
    #|    .dot { width: 8px; height: 8px; border-radius: 50%; background: #24272b; }
    #|    .actions {
    #|      margin-left: auto;
    #|      display: flex;
    #|      align-items: center;
    #|      gap: 13px;
    #|    }
    #|    .actions svg {
    #|      width: 17px;
    #|      height: 17px;
    #|      fill: none;
    #|      stroke: currentColor;
    #|      stroke-width: 1.6;
    #|      stroke-linecap: round;
    #|      stroke-linejoin: round;
    #|    }
    #|    .divider { width: 1px; height: 18px; background: #c7c9cc; }
    #|    main {
    #|      min-height: calc(100vh - 30px);
    #|      display: grid;
    #|      place-items: center;
    #|      padding: 48px 32px 64px;
    #|      text-align: center;
    #|    }
    #|    h1 { margin: 0 0 8px; font-size: 25px; font-weight: 620; letter-spacing: -.025em; }
    #|    p { margin: 0; color: #777b80; font-size: 13px; }
    #|  </style>
    #|</head>
    #|<body>
    #|  <header class="titlebar">
    #|    <div class="history">
    #|      <svg viewBox="0 0 20 20"><path d="m13 3-7 7 7 7"/></svg>
    #|      <svg class="disabled" viewBox="0 0 20 20"><path d="m7 3 7 7-7 7"/></svg>
    #|    </div>
    #|    <div class="command"><div class="branch">fix-titlebar</div><div class="count"><i class="dot"></i>6</div></div>
    #|    <div class="actions">
    #|      <svg viewBox="0 0 20 20"><path d="M3 4h6v12H3zM11 4h6v5h-6zM11 11h6v5h-6z"/></svg>
    #|      <span class="divider"></span>
    #|      <svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="7.5"/><circle cx="10" cy="7.5" r="2.2"/><path d="M5.8 15.2c.9-2.4 2.3-3.5 4.2-3.5s3.3 1.1 4.2 3.5"/></svg>
    #|      <svg viewBox="0 0 20 20"><path d="m10 2.5 1.5 2 2.5-.2.7 2.4 2.2 1.2-1 2.3 1 2.3-2.2 1.2-.7 2.4-2.5-.2-1.5 2-1.5-2-2.5.2-.7-2.4-2.2-1.2 1-2.3-1-2.3 2.2-1.2.7-2.4 2.5.2z"/><circle cx="10" cy="10" r="2"/></svg>
    #|    </div>
    #|  </header>
    #|  <main><div><h1>沉浸式标题栏</h1><p>网页内容已延伸到 macOS 原生标题栏下方</p></div></main>
    #|</body>
    #|</html>
  @proton.html("Proton Overlay", html, width=800, height=520, debug=true)
  .titlebar_style(@proton.TitlebarStyle::Overlay)
  .run_or_abort()
}
