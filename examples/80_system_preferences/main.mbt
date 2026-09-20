///|
struct ReadRequest {} derive(ToJson, FromJson)

///|
pub extend ReadRequest with ToJson::{to_json}

///|
pub extend ReadRequest with FromJson::{from_json}

///|
struct TrustRequest {
  prompt : Bool
} derive(ToJson, FromJson)

///|
pub extend TrustRequest with ToJson::{to_json}

///|
pub extend TrustRequest with FromJson::{from_json}

///|
/// One readback of every system preference query. A query that the platform
/// does not answer keeps its value empty and reports the error instead, so the
/// page can show the platform matrix without a second round trip.
struct Snapshot {
  accent_color : String
  accent_error : String
  rich_animation : Bool
  scroll_animations : Bool
  reduced_motion : Bool
  animation_error : String
  microphone : String
  camera : String
  screen : String
  media_error : String
} derive(ToJson, FromJson)

///|
pub extend Snapshot with ToJson::{to_json}

///|
pub extend Snapshot with FromJson::{from_json}

///|
struct TrustReply {
  trusted : Bool
  error : String
} derive(ToJson, FromJson)

///|
pub extend TrustReply with ToJson::{to_json}

///|
pub extend TrustReply with FromJson::{from_json}

///|
let system_preferences_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/system-preferences",
  js_namespace="systemPreferences",
)

///|
let read_command : @proton_contract.Command[ReadRequest, Snapshot] = system_preferences_contract.command(
  "read",
)

///|
let trust_command : @proton_contract.Command[TrustRequest, TrustReply] = system_preferences_contract.command(
  "trust",
)

///|
fn media_label(status : @proton.MediaAccessStatus) -> String {
  match status {
    Unknown => "unknown"
    NotDetermined => "not-determined"
    Granted => "granted"
    Denied => "denied"
    Restricted => "restricted"
  }
}

///|
/// Reads one media kind. The status vocabulary is Electron's, so the strings
/// the page shows can be compared with `systemPreferences`
/// `getMediaAccessStatus` output directly.
fn read_media(
  kind : @proton.MediaAccessKind,
) -> String raise @proton.SystemPreferencesError {
  media_label(@proton.system_media_access_status(kind))
}

///|
fn read_snapshot() -> Snapshot {
  let mut accent_color = ""
  let mut accent_error = ""
  accent_color = @proton.system_accent_color() catch {
    error => {
      accent_error = error.message()
      ""
    }
  }
  let mut rich_animation = false
  let mut scroll_animations = false
  let mut reduced_motion = false
  let mut animation_error = ""
  try @proton.system_animation_settings() catch {
    error => animation_error = error.message()
  } noraise {
    settings => {
      rich_animation = settings.should_render_rich_animation
      scroll_animations = settings.scroll_animations_enabled_by_system
      reduced_motion = settings.prefers_reduced_motion
    }
  }
  let mut microphone = ""
  let mut camera = ""
  let mut screen = ""
  let mut media_error = ""
  microphone = read_media(@proton.MediaAccessKind::Microphone) catch {
    error => {
      media_error = error.message()
      ""
    }
  }
  camera = read_media(@proton.MediaAccessKind::Camera) catch {
    error => {
      media_error = error.message()
      ""
    }
  }
  screen = read_media(@proton.MediaAccessKind::Screen) catch {
    error => {
      media_error = error.message()
      ""
    }
  }
  {
    accent_color,
    accent_error,
    rich_animation,
    scroll_animations,
    reduced_motion,
    animation_error,
    microphone,
    camera,
    screen,
    media_error,
  }
}

///|
fn read_trust(prompt : Bool) -> TrustReply {
  let trusted = @proton.system_is_trusted_accessibility_client(prompt) catch {
    error => return { trusted: false, error: error.message(), }
  }
  { trusted, error: "", }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(read_command, (_context, _request) => read_snapshot())
  registrar.bind(trust_command, (_context, request) => {
    read_trust(request.prompt)
  })
}

///|
fn html() -> String {
  (
    #|<!doctype html>
    #|<html lang="en">
    #|  <head>
    #|    <meta charset="utf-8">
    #|    <meta name="viewport" content="width=device-width, initial-scale=1">
    #|    <title>System Preferences</title>
    #|    <style>
    #|      :root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; background: #0e1216; color: #eef3f6; }
    #|      * { box-sizing: border-box; }
    #|      body { margin: 0; min-height: 100vh; background: #0e1216; }
    #|      button { font: inherit; }
    #|      main { width: min(1000px, calc(100vw - 40px)); margin: 0 auto; padding: 34px 0 46px; }
    #|      header { display: flex; align-items: end; justify-content: space-between; gap: 24px; padding-bottom: 20px; border-bottom: 1px solid #2b353d; }
    #|      .eyebrow { margin: 0 0 8px; color: #58c7d8; font: 700 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; letter-spacing: .16em; text-transform: uppercase; }
    #|      h1 { margin: 0; font-size: clamp(28px, 4.4vw, 44px); line-height: 1; letter-spacing: -.045em; }
    #|      .summary { max-width: 560px; margin: 12px 0 0; color: #9fb0bd; line-height: 1.55; }
    #|      .layout { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; margin-top: 18px; }
    #|      .panel { display: flex; flex-direction: column; border: 1px solid #2b353d; border-radius: 12px; background: #151b21; overflow: hidden; }
    #|      .panel-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; min-height: 46px; padding: 0 16px; border-bottom: 1px solid #2b353d; color: #9fb0bd; font: 650 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; text-transform: uppercase; letter-spacing: .09em; }
    #|      .panel-body { flex: 1; padding: 16px; }
    #|      .row { display: flex; align-items: center; justify-content: space-between; gap: 14px; min-height: 32px; }
    #|      .row + .row { margin-top: 4px; }
    #|      .row span:first-child { color: #9fb0bd; }
    #|      .value { font: 700 14px/1.3 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .value.yes { color: #7ee0a2; }
    #|      .value.no { color: #e6b566; }
    #|      .accent { display: flex; align-items: center; gap: 14px; }
    #|      .swatch { width: 64px; height: 64px; border: 1px solid #38505c; border-radius: 12px; background: #1d252b; }
    #|      .accent-code { font: 700 15px/1.4 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .hint { margin: 14px 0 0; color: #7d8f9c; font-size: 12.5px; line-height: 1.5; }
    #|      .demo { position: relative; height: 74px; margin-top: 18px; border: 1px solid #2b353d; border-radius: 10px; background: #101519; overflow: hidden; }
    #|      .demo::after { content: ""; position: absolute; top: 50%; left: 0; width: 62px; height: 62px; margin-top: -31px; border-radius: 50%; background: radial-gradient(circle at 34% 32%, #7ee0a2, #1d7a54 70%); box-shadow: 0 0 26px #1d7a5488; animation: travel 2.4s ease-in-out infinite alternate; }
    #|      .reduce-motion .demo::after { animation-play-state: paused; }
    #|      @keyframes travel { from { left: 6px; } to { left: calc(100% - 68px); } }
    #|      .errors { flex: 1; padding: 15px 16px; }
    #|      .errors h2 { margin: 0 0 10px; color: #9fb0bd; font: 650 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; text-transform: uppercase; letter-spacing: .09em; }
    #|      .errors ul { display: grid; gap: 7px; margin: 0; padding: 0; list-style: none; }
    #|      .errors li { border-left: 2px solid #e6b566; padding: 6px 9px; background: #1b2228; color: #d7c39a; font: 11.5px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; overflow-wrap: anywhere; }
    #|      .errors li.empty { border-color: #3b4a55; color: #7d8f9c; }
    #|      .controls { display: flex; flex-wrap: wrap; align-items: center; gap: 9px; padding: 14px 16px; border-top: 1px solid #2b353d; }
    #|      button { min-height: 40px; border: 1px solid #3f5a68; border-radius: 8px; padding: 0 14px; background: #1d2a32; color: #eef3f6; font-weight: 700; cursor: pointer; }
    #|      button:hover { border-color: #58c7d8; background: #22343d; }
    #|      button:focus-visible { outline: 3px solid #58c7d866; outline-offset: 2px; }
    #|      button.primary { border-color: #2f8f6b; background: #1d5b42; }
    #|      #status { margin-left: auto; color: #7d8f9c; font: 12px/1.4 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      @media (max-width: 780px) { header { align-items: start; flex-direction: column; } .layout { grid-template-columns: 1fr; } }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <header>
    #|        <div>
    #|          <p class="eyebrow">Native surface / manual test 80</p>
    #|          <h1>System preferences</h1>
    #|          <p class="summary">Live readback of the Electron <code>systemPreferences</code> surface Proton implements: accent color, animation guidance, media consent, and accessibility trust.</p>
    #|        </div>
    #|      </header>
    #|      <div class="layout">
    #|        <section class="panel">
    #|          <div class="panel-head"><strong>Accent color</strong><span id="accent-state">-</span></div>
    #|          <div class="panel-body">
    #|            <div class="accent">
    #|              <div id="swatch" class="swatch"></div>
    #|              <div>
    #|                <div id="accent-code" class="accent-code">-</div>
    #|                <div class="hint">RGBA digits without a leading <code>#</code>, the form <code>systemPreferences.getAccentColor()</code> returns.</div>
    #|              </div>
    #|            </div>
    #|            <p class="hint">Windows: Settings &rarr; Personalization &rarr; Colors &rarr; Accent color. macOS: System Settings &rarr; Appearance &rarr; Accent color. Re-read after changing it.</p>
    #|          </div>
    #|        </section>
    #|        <section class="panel">
    #|          <div class="panel-head"><strong>Animation settings</strong><span id="animation-state">-</span></div>
    #|          <div class="panel-body">
    #|            <div class="row"><span>shouldRenderRichAnimation</span><span id="rich" class="value">-</span></div>
    #|            <div class="row"><span>scrollAnimationsEnabledBySystem</span><span id="scroll" class="value">-</span></div>
    #|            <div class="row"><span>prefersReducedMotion</span><span id="reduced" class="value">-</span></div>
    #|            <div class="demo"></div>
    #|            <p class="hint">Windows: Settings &rarr; Accessibility &rarr; Visual effects &rarr; Animation effects. macOS: System Settings &rarr; Accessibility &rarr; Display &rarr; Reduce motion. Re-read after changing it: the marker stops when the system asks for reduced motion.</p>
    #|          </div>
    #|        </section>
    #|        <section class="panel">
    #|          <div class="panel-head"><strong>Media access</strong><span id="media-state">-</span></div>
    #|          <div class="panel-body">
    #|            <div class="row"><span>microphone</span><span id="microphone" class="value">-</span></div>
    #|            <div class="row"><span>camera</span><span id="camera" class="value">-</span></div>
    #|            <div class="row"><span>screen</span><span id="screen" class="value">-</span></div>
    #|            <p class="hint">Windows: Settings &rarr; Privacy &amp; security &rarr; Microphone / Camera. macOS: System Settings &rarr; Privacy &amp; Security &rarr; Microphone / Camera / Screen Recording. Linux reports an error, matching Electron's platform support.</p>
    #|          </div>
    #|        </section>
    #|        <section class="panel">
    #|          <div class="panel-head"><strong>Accessibility trust</strong><span id="trust-state">-</span></div>
    #|          <div class="panel-body">
    #|            <div class="row"><span>isTrustedAccessibilityClient</span><span id="trust" class="value">-</span></div>
    #|            <p class="hint">macOS owns this query. The first button asks without prompting; the second one passes <code>prompt: true</code>, which is the call that opens the system dialog and the Accessibility settings pane.</p>
    #|          </div>
    #|          <div class="controls">
    #|            <button id="trust-quiet" type="button">Check silently</button>
    #|            <button id="trust-prompt" type="button">Check with prompt</button>
    #|          </div>
    #|        </section>
    #|        <section class="panel">
    #|          <div class="panel-head"><strong>Platform errors</strong><span>envelopes reported to the page</span></div>
    #|          <div class="errors">
    #|            <h2>Query errors</h2>
    #|            <ul id="errors"><li class="empty">No error reported by this platform.</li></ul>
    #|          </div>
    #|          <div class="controls">
    #|            <button class="primary" id="reload" type="button">Re-read all values</button>
    #|            <div id="status" role="status" aria-live="polite">reading...</div>
    #|          </div>
    #|        </section>
    #|      </div>
    #|    </main>
    #|    <script>
    #|      const invoke = (route, payload) => window.__MoonBit__.core.invokeOp(route, payload);
    #|      const status = document.querySelector("#status");
    #|      const errors = document.querySelector("#errors");
    #|      const text = (id, value) => { document.querySelector(`#${id}`).textContent = value; };
    #|      const flag = (id, value) => {
    #|        const node = document.querySelector(`#${id}`);
    #|        node.textContent = value ? "true" : "false";
    #|        node.className = `value ${value ? "yes" : "no"}`;
    #|      };
    #|      function collect(entries) {
    #|        const reported = entries.filter(([, message]) => message.length > 0);
    #|        if (reported.length === 0) {
    #|          errors.innerHTML = '<li class="empty">No error reported by this platform.</li>';
    #|          return;
    #|        }
    #|        errors.innerHTML = "";
    #|        for (const [label, message] of reported) {
    #|          const item = document.createElement("li");
    #|          item.textContent = `${label}: ${message}`;
    #|          errors.append(item);
    #|        }
    #|      }
    #|      function render(snapshot) {
    #|        const accent = snapshot.accent_color;
    #|        text("accent-code", accent.length > 0 ? accent : "(no accent color)");
    #|        document.querySelector("#swatch").style.background = accent.length >= 6 ? `#${accent.slice(0, 6)}` : "#1d252b";
    #|        text("accent-state", accent.length > 0 ? "rgba" : "empty");
    #|        flag("rich", snapshot.rich_animation);
    #|        flag("scroll", snapshot.scroll_animations);
    #|        flag("reduced", snapshot.reduced_motion);
    #|        document.body.classList.toggle("reduce-motion", snapshot.reduced_motion);
    #|        text("animation-state", snapshot.animation_error.length > 0 ? "error" : "ok");
    #|        text("microphone", snapshot.microphone.length > 0 ? snapshot.microphone : "-");
    #|        text("camera", snapshot.camera.length > 0 ? snapshot.camera : "-");
    #|        text("screen", snapshot.screen.length > 0 ? snapshot.screen : "-");
    #|        text("media-state", snapshot.media_error.length > 0 ? "unsupported" : "ok");
    #|        collect([
    #|          ["accent color", snapshot.accent_error],
    #|          ["animation settings", snapshot.animation_error],
    #|          ["media access", snapshot.media_error],
    #|        ]);
    #|      }
    #|      function renderTrust(reply) {
    #|        const node = document.querySelector("#trust");
    #|        node.textContent = reply.error.length > 0 ? "unsupported" : String(reply.trusted);
    #|        node.className = `value ${reply.error.length > 0 ? "no" : "yes"}`;
    #|        text("trust-state", reply.error.length > 0 ? "error" : "ok");
    #|        collect([["accessibility trust", reply.error]]);
    #|      }
    #|      async function readAll(label) {
    #|        status.textContent = label;
    #|        try {
    #|          render(await invoke("ext:systemPreferences/read", {}));
    #|          status.textContent = `${label} - done`;
    #|        } catch (error) {
    #|          status.textContent = `${label} failed: ${String(error)}`;
    #|        }
    #|      }
    #|      async function readTrust(prompt) {
    #|        status.textContent = prompt ? "requesting accessibility trust..." : "reading accessibility trust...";
    #|        try {
    #|          renderTrust(await invoke("ext:systemPreferences/trust", { prompt }));
    #|          status.textContent = "accessibility trust read";
    #|        } catch (error) {
    #|          status.textContent = `accessibility trust failed: ${String(error)}`;
    #|        }
    #|      }
    #|      document.querySelector("#reload").addEventListener("click", () => void readAll("re-reading platform values"));
    #|      document.querySelector("#trust-quiet").addEventListener("click", () => void readTrust(false));
    #|      document.querySelector("#trust-prompt").addEventListener("click", () => void readTrust(true));
    #|      void readAll("reading platform values");
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
async fn main {
  @proton.html("System Preferences", html(), width=980, height=780, debug=true)
  .identifier("dev.proton.system-preferences")
  .commands(register_commands)
  .run_or_abort()
}
