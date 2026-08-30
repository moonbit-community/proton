///|
struct Request {
  action : String
  profile : String
} derive(ToJson, FromJson)

///|
pub extend Request with ToJson::{to_json}

///|
pub extend Request with FromJson::{from_json}

///|
struct Reply {
  ok : Bool
  request_id : Int
  message : String
} derive(ToJson, FromJson)

///|
pub extend Reply with ToJson::{to_json}

///|
pub extend Reply with FromJson::{from_json}

///|
let contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/print-pdf",
  js_namespace="printReview",
)

///|
let command : @proton_contract.Command[Request, Reply] = contract.command("run")

///|
let browser_slot : Ref[@proton.BrowserHandle?] = { val: None, }

///|
fn temporary_directory() -> String {
  let variable = if @path.sep == '\\' { "TEMP" } else { "TMPDIR" }
  @env.get_env_var(variable).unwrap_or_else(() => {
    if @path.sep == '\\' {
      @env.current_dir().unwrap_or(".")
    } else {
      "/tmp"
    }
  })
}

///|
let pdf_path : String = {
  let directory = temporary_directory()
  if directory.has_suffix(@path.sep.to_string()) {
    directory + "proton-print-review.pdf"
  } else {
    directory + @path.sep.to_string() + "proton-print-review.pdf"
  }
}

///|
fn js_escape(text : String) -> String {
  text
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="\"", new="\\\"")
  .replace_all(old="\n", new="\\n")
  .replace_all(old="\r", new="\\r")
}

///|
fn show_status(message : String) -> Unit {
  match browser_slot.val {
    Some(browser) =>
      browser.eval(
        "document.querySelector(\"#status\").textContent = \"\{js_escape(message)}\";",
      ) catch {
        _ => ()
      }
    None => ()
  }
}

///|
fn pdf_options(profile : String) -> @proton.PdfPrintOptions {
  match profile {
    "landscape" =>
      @proton.PdfPrintOptions(
        landscape=true,
        print_background=true,
        scale=0.9,
        paper_width=8.5,
        paper_height=11.0,
        margins=@proton.PdfPrintMargins::Custom(
          top=0.35,
          right=0.35,
          bottom=0.35,
          left=0.35,
        ),
        generate_tagged_pdf=true,
        generate_document_outline=true,
      )
    "css" =>
      @proton.PdfPrintOptions(
        print_background=true,
        prefer_css_page_size=true,
        margins=@proton.PdfPrintMargins::NoMargins,
        generate_tagged_pdf=true,
        generate_document_outline=true,
      )
    _ =>
      @proton.PdfPrintOptions(
        print_background=true,
        margins=@proton.PdfPrintMargins::Custom(
          top=0.5,
          right=0.5,
          bottom=0.55,
          left=0.5,
        ),
        display_header_footer=true,
        header_template="<div style='font-size:8px;width:100%;text-align:center;color:#53616a'><span class='title'></span></div>",
        footer_template="<div style='font-size:8px;width:100%;text-align:center;color:#53616a'><span class='pageNumber'></span> / <span class='totalPages'></span></div>",
        generate_tagged_pdf=true,
        generate_document_outline=true,
      )
  }
}

///|
fn run(request : Request) -> Reply {
  match browser_slot.val {
    Some(browser) =>
      try {
        if request.action == "print" {
          browser.print()
          { ok: true, request_id: 0, message: "System print flow opened", }
        } else {
          let request_id = browser.print_to_pdf(
            pdf_path,
            options=pdf_options(request.profile),
          )
          {
            ok: true,
            request_id,
            message: "PDF request \{request_id} started",
          }
        }
      } catch {
        error => { ok: false, request_id: 0, message: error.to_string(), }
      }
    None => { ok: false, request_id: 0, message: "browser is not ready", }
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(command, (_context, request) => run(request))
}

///|
fn page() -> String {
  (
    #|<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Proton Print Calibration</title>
    #|<style>:root{font-family:"Avenir Next",Avenir,Arial,sans-serif;color:#18242b;background:#dfe5e7}*{box-sizing:border-box}body{margin:0}.controls{position:sticky;top:0;z-index:2;display:grid;grid-template-columns:1fr auto;gap:18px;align-items:center;padding:16px 24px;background:#18242b;color:#f7f7f2;border-bottom:4px solid #1d7a8c}.controls strong{font-size:15px}.controls small{display:block;color:#b9c5c9;margin-top:3px}.actions{display:flex;gap:8px;align-items:center}select,button{height:38px;border:1px solid #8fa1a7;border-radius:3px;background:#f7f7f2;color:#18242b;padding:0 12px;font-weight:700}button{cursor:pointer}button.primary{background:#1d7a8c;color:white;border-color:#1d7a8c}#status{grid-column:1/-1;margin:0;color:#d2e7eb;font:12px/1.4 "SFMono-Regular",Consolas,monospace}.document{padding:34px}.sheet{width:min(100%,820px);min-height:980px;margin:0 auto 28px;background:#f7f7f2;padding:58px 64px;box-shadow:0 8px 30px #18242b26}.masthead{display:grid;grid-template-columns:1fr auto;align-items:end;border-bottom:5px solid #18242b;padding-bottom:18px}.kicker{font:700 11px "SFMono-Regular",Consolas,monospace;color:#1d7a8c}.masthead h1{margin:5px 0 0;font:700 46px/1.05 Georgia,serif}.edition{text-align:right;font:12px/1.45 "SFMono-Regular",Consolas,monospace}.lead{font:22px/1.45 Georgia,serif;margin:38px 0}.lead code{font:0.78em "SFMono-Regular",Consolas,monospace}.calibration{display:grid;grid-template-columns:repeat(4,1fr);height:42px;margin:28px 0}.calibration span:nth-child(1){background:#1d7a8c}.calibration span:nth-child(2){background:#b33f62}.calibration span:nth-child(3){background:#e1b341}.calibration span:nth-child(4){background:#18242b}.grid{display:grid;grid-template-columns:1.4fr 1fr;gap:36px}.grid h2{font:700 24px Georgia,serif;margin:0 0 12px}.grid p,.grid li{font-size:14px;line-height:1.65}.metrics{border-left:2px solid #18242b;padding-left:24px}.metric{border-bottom:1px solid #9eaaae;padding:13px 0}.metric b{display:block;font:700 22px Georgia,serif}.page-two{page-break-before:always}.proof{margin-top:40px;border-top:1px solid #18242b;border-bottom:1px solid #18242b;padding:24px 0;display:grid;grid-template-columns:repeat(3,1fr);gap:22px}.proof b{font:700 30px Georgia,serif}.footer-mark{margin-top:70px;font:11px "SFMono-Regular",Consolas,monospace;color:#53616a}@media(max-width:700px){.controls{grid-template-columns:1fr}.actions{flex-wrap:wrap}.document{padding:14px}.sheet{padding:34px 28px}.masthead,.grid{grid-template-columns:1fr}.edition{text-align:left;margin-top:16px}.masthead h1{font-size:36px}}@media print{:root,body,.document{background:#fff}.controls{display:none}.document{padding:0}.sheet{width:auto;min-height:0;margin:0;box-shadow:none;padding:0}.page-two{page-break-before:always}}</style></head>
    #|<body><section class="controls"><div><strong>Print calibration</strong><small>System dialog and PDF output use the same browser contents.</small></div><div class="actions"><select id="profile"><option value="standard">Letter + header/footer</option><option value="landscape">Landscape + background</option><option value="css">CSS A4 page size</option></select><button id="print">System print</button><button class="primary" id="pdf">Create PDF</button></div><p id="status" role="status" aria-live="polite">Ready. PDF path: \{pdf_path}</p></section><main class="document"><article class="sheet"><header class="masthead"><div><div class="kicker">PROTON OUTPUT LAB / REVIEW 72</div><h1>Browser print proof</h1></div><div class="edition">MOONBIT NATIVE<br>COLOR EDITION</div></header><p class="lead">A practical sheet for checking page geometry, background graphics, typography, and asynchronous completion.</p><div class="calibration" aria-label="Cyan magenta yellow and black calibration strip"><span></span><span></span><span></span><span></span></div><section class="grid"><div><h2>What this page proves</h2><p>The browser remains on screen while Proton opens the platform print flow or writes a PDF to a chosen path. The PDF callback reports the original request id and final status.</p><ul><li>Dark ink remains crisp against the paper field.</li><li>The four-color strip confirms background printing.</li><li>Headings and body copy expose font substitution or clipping.</li></ul></div><aside class="metrics"><div class="metric"><b>8.5 x 11</b>standard paper in inches</div><div class="metric"><b>1-2</b>expected pages</div><div class="metric"><b>100%</b>default scale</div></aside></section><p class="footer-mark">PAGE ONE / GEOMETRY AND COLOR</p></article><article class="sheet page-two"><header class="masthead"><div><div class="kicker">SECOND PAGE / RANGE CHECK</div><h1>Pagination stays deliberate</h1></div><div class="edition">OUTLINE<br>TAGGED PDF</div></header><div class="proof"><div><b>01</b><p>Page break begins a clean second sheet.</p></div><div><b>02</b><p>Margins keep every edge comfortably visible.</p></div><div><b>03</b><p>Footer numbering should report two pages.</p></div></div><p class="lead">Use the CSS A4 profile to confirm that <code>@page</code> overrides the default paper size without scaling this layout into an unexpected frame.</p><p class="footer-mark">PAGE TWO / PAGINATION AND METADATA</p></article></main>
    #|<script>const status=document.querySelector('#status');function applyPageProfile(profile){document.querySelector('#css-page-size')?.remove();if(profile==='css'){const style=document.createElement('style');style.id='css-page-size';style.textContent='@page{size:A4;margin:14mm}';document.head.appendChild(style)}}async function run(action){const profile=document.querySelector('#profile').value;applyPageProfile(profile);status.textContent=action==='print'?'Opening system print flow...':'Creating PDF...';try{const reply=await window.__MoonBit__.core.invokeOp('ext:printReview/run',{action,profile});status.textContent=reply.message}catch(error){status.textContent=String(error)}}document.querySelector('#print').onclick=()=>void run('print');document.querySelector('#pdf').onclick=()=>void run('pdf')</script></body></html>
  )
}

///|
async fn main {
  @proton.html("Print and PDF", page(), width=1040, height=760, debug=true)
  .commands(register_commands)
  .on_browser_event(async fn(_browser, event) noraise {
    if event is @proton.BrowserEvent::PdfPrinted(result~) {
      show_status(
        "PDF request \{result.request_id}: \{if result.success { "complete" } else { "failed" }}\nPath: \{result.path}",
      )
    }
  })
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      browser_slot.val = Some(window.browser())
      window
    },
    on_close=fn(_window) { browser_slot.val = None },
  )
  .identifier("dev.proton.72-print-pdf")
  .run_or_abort()
}
