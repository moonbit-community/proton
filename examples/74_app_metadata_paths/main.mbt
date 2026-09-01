///|
fn html_escape(value : String) -> String {
  value
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
}

///|
fn path_row(label : String, value : String) -> String {
  "<tr><th scope=\"row\">" +
  html_escape(label) +
  "</th><td>" +
  html_escape(value) +
  "</td></tr>"
}

///|
fn display_path(app : @proton.App, kind : @proton.AppPathKind) -> String {
  app.path(kind) catch {
    @proton.UnsupportedPath(..) => "Not available on this platform"
    error => abort(error.message())
  }
}

///|
fn apply_path_overrides(
  app : @proton.App,
  root : String,
) -> @proton.App raise @proton.AppPathError {
  let logs = @mbpath.Path(root).join("logs").normalize().to_string()
  app
  .set_path(@proton.AppPathKind::UserData, root)
  .set_path(@proton.AppPathKind::Downloads, root)
  .set_app_logs_path(path=logs)
}

///|
fn review_page(
  name : String,
  version : String,
  packaged : Bool,
  override_root : String?,
  application_path : String,
  paths : Array[(String, String)],
) -> String {
  let rows = paths.map(entry => path_row(entry.0, entry.1)).join("")
  let override_row = match override_root {
    Some(root) => path_row("Override root", root)
    None => ""
  }
  let mode = if packaged { "Packaged" } else { "Development" }
  let mode_class = if packaged { "packaged" } else { "development" }
  let path_mode = if override_root is Some(_) {
    "Custom overrides"
  } else {
    "Platform defaults"
  }
  (
    $|<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Application metadata</title>
    $|<style>*{box-sizing:border-box}:root{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#20272b;background:#edf0f1}body{margin:0;min-height:100vh;background:#edf0f1}header{padding:30px 38px 26px;background:#20272b;color:#f8fafb;border-bottom:5px solid #c94f3d}.eyebrow{font:700 11px/1.4 ui-monospace,SFMono-Regular,Consolas,monospace;color:#75d5b4;text-transform:uppercase}h1{margin:6px 0 8px;font-size:30px;letter-spacing:0}header p{margin:0;color:#c7d0d4}.summary{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:1px;background:#aab3b7;border-bottom:1px solid #aab3b7}.metric{min-width:0;padding:20px 24px;background:#fff}.metric span{display:block;margin-bottom:5px;color:#657178;font-size:12px;font-weight:700;text-transform:uppercase}.metric strong{display:block;overflow-wrap:anywhere;font-size:18px}.mode{display:inline-flex!important;width:max-content;padding:3px 8px;border-radius:3px;color:#fff!important}.mode.development{background:#2d6f86}.mode.packaged{background:#237653}main{padding:26px 38px 38px}h2{margin:0 0 14px;font-size:18px}table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #aab3b7;table-layout:fixed}th,td{padding:13px 16px;border-bottom:1px solid #d8dddf;text-align:left;vertical-align:top}th{width:180px;color:#4d5a61;font-size:13px}td{overflow-wrap:anywhere;font:13px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace;color:#183e4d}tr:last-child th,tr:last-child td{border-bottom:0}.note{margin:16px 0 0;padding-left:14px;border-left:4px solid #d6a537;color:#536168;font-size:13px;line-height:1.55}@media(max-width:780px){header,main{padding-left:20px;padding-right:20px}.summary{grid-template-columns:1fr 1fr}.metric{padding:16px 20px}th{width:120px}}@media(max-width:480px){.summary{grid-template-columns:1fr}}</style></head>
    $|<body><header><span class="eyebrow">Electron app parity / Review 74</span><h1>Application metadata and paths</h1><p>Values resolved by the Proton root facade before runtime startup.</p></header><section class="summary"><div class="metric"><span>Product name</span><strong>\{html_escape(name)}</strong></div><div class="metric"><span>Version</span><strong>\{html_escape(version)}</strong></div><div class="metric"><span>Execution</span><strong class="mode \{mode_class}">\{mode}</strong></div><div class="metric"><span>Path mode</span><strong>\{html_escape(path_mode)}</strong></div></section><main><h2>Resolved locations</h2><table><tbody>\{override_row}\{path_row("App path", application_path)}\{rows}</tbody></table><p class="note">User data, session data, and logs use the stable reverse-DNS identifier by default. Override mode verifies that dependent runtime paths consume the configured locations.</p></main></body></html>
  )
}

///|
async fn main {
  let base = @proton.html(
      "Application Metadata And Paths",
      "<main>Loading application metadata...</main>",
      width=980,
      height=720,
    )
    .load_config()
    .single_instance()
  let override_root = @env.get_env_var("PROTON_APP_PATH_OVERRIDE_ROOT")
  let app = match override_root {
    Some(root) => apply_path_overrides(base, root)
    None => base
  }
  let name = app.name() catch { error => abort(error.message()) }
  let version = app.version() catch { error => abort(error.message()) }
  let kinds : Array[(@proton.AppPathKind, String)] = [
    (@proton.AppPathKind::Home, "Home"),
    (@proton.AppPathKind::AppData, "App data"),
    (@proton.AppPathKind::UserData, "User data"),
    (@proton.AppPathKind::SessionData, "Session data"),
    (@proton.AppPathKind::Temp, "Temp"),
    (@proton.AppPathKind::Executable, "Executable"),
    (@proton.AppPathKind::Logs, "Logs"),
    (@proton.AppPathKind::Assets, "Assets"),
    (@proton.AppPathKind::Module, "Module"),
    (@proton.AppPathKind::Desktop, "Desktop"),
    (@proton.AppPathKind::Documents, "Documents"),
    (@proton.AppPathKind::Downloads, "Downloads"),
    (@proton.AppPathKind::Music, "Music"),
    (@proton.AppPathKind::Pictures, "Pictures"),
    (@proton.AppPathKind::Videos, "Videos"),
    (@proton.AppPathKind::Recent, "Recent"),
  ]
  let paths = kinds.map(entry => (entry.1, display_path(app, entry.0)))
  app
  .entry_html(
    review_page(
      name,
      version,
      @proton.is_packaged(),
      override_root,
      @proton.app_path(),
      paths,
    ),
  )
  .run_or_abort()
}
