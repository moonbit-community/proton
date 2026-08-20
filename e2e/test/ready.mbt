///|
async fn wait_for_ready(
  page : @client.CdpClient,
  expression : String,
  timeout : Int,
) -> Unit {
  let attempts = timeout / 100
  for attempt in 0..<=attempts {
    if evaluate_bool_while_context_available(page, expression) {
      return
    }
    if attempt < attempts {
      @async.sleep(100)
    }
  }
  fail("CDP e2e timed out waiting for ready expression: " + expression)
}

///|
fn scenario_ready_expression(name : String) -> String raise {
  match name {
    "41_app_commands" =>
      "Boolean(window.__MoonBit__ && window.__MoonBit__.core && window.__MoonBit__.core.invokeOp)"
    "38_async_extension_add" =>
      "Boolean(window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.add?.slowAdd)"
    "39_sync_async_extensions" =>
      "Boolean(window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.math?.double && window.__MoonBit__?.add?.slowAdd)"
    "40_event_broadcast" =>
      "Boolean(window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.ticker?.start && window.__MoonBit__?.ticker?.on)"
    "46_asset_sidecar_resources" =>
      "Boolean(window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.add?.add && window.__MoonBit__?.add?.addLater && window.__MoonBit__?.add?.reportProbe && document.querySelector('#log')?.textContent === 'Bridge ready.')"
    "47_dev_extension_js" =>
      "Boolean(window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.ticker?.start && window.__MoonBit__?.ticker?.on && document.querySelector('#bridge-status')?.dataset.ready === 'true')"
    "42_attribute_codegen_commands" =>
      "Boolean(window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.add?.slowAdd && window.__MoonBit__?.events?.on)"
    "52_web_contents_view" =>
      "['Web Contents View Host','WCV Left','WCV Right'].includes(document.title) && document.readyState === 'complete'"
    "54_devtools" =>
      "document.title === 'Proton DevTools API' && typeof window.__MoonBit__?.core?.invokeOp === 'function'"
    "56_i18n" =>
      "document.title === 'Proton I18n E2E' && document.readyState === 'complete'"
    _ => fail("unsupported E2E scenario: " + name)
  }
}
