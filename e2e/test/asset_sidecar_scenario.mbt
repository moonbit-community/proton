///|
struct AssetSidecarScenarioProbe {
  url : String
  pathname : String
  title : String
  has_bridge : Bool
  has_generated_proxy : Bool
  has_delayed_proxy : Bool
  has_report_proxy : Bool
  instant_result : String
  delayed_result : String
  log_text : String
  css_loaded : Bool
  script_element_present : Bool
  worker_reply : String
  command_reply : Int
  delayed_reply : Int
} derive(FromJson, Eq, Debug)

///|
pub extend AssetSidecarScenarioProbe with Eq::{not_equal, equal}

///|
pub extend AssetSidecarScenarioProbe with Debug::{to_repr}

///|
pub extend AssetSidecarScenarioProbe with FromJson::{from_json}

///|
async fn run_asset_sidecar_scenario_page_probe(
  tasks : @async.TaskGroup[Unit],
  app : SpawnedScenarioApp,
  target : String,
  timeout : Int,
) -> Unit {
  let page = connect_spawned_page(tasks, app, target, timeout)
  defer page.close()
  wait_for_ready(
    page,
    scenario_ready_expression("46_asset_sidecar_resources"),
    timeout,
  )
  wait_for_cdp_expression(
    page, "document.querySelector('#log')?.textContent === 'Bridge ready.'", "asset sidecar bridge ready",
    timeout,
  )
  let value = evaluate_json(page, asset_sidecar_probe_expression(), true)
  let result : AssetSidecarScenarioProbe = decode_probe(value, "asset sidecar")
  assert_asset_sidecar_probe(result, value)
  ignore(
    evaluate_json(
      page, "location.href = new URL('navigated.html', location.href).href", false,
    ),
  )
  wait_for_cdp_expression(
    page, "document.title === 'Asset Navigation Complete' && document.querySelector('#navigation-result')?.textContent === 'Navigated with bridge: 42'",
    "asset document navigation with bridge", timeout,
  )
  assert_asset_sidecar_native_log(app.native_log_path)
  ignore(page.navigate("https://proton.localhost/missing.html"))
  wait_for_cdp_expression(
    page, "location.pathname === '/missing.html' && document.body?.textContent === 'Not Found'",
    "asset sidecar local 404", timeout,
  )
  guard app_exit_code(app.process) is None else {
    fail(
      "failed asset navigation terminated the application" +
      app_diagnostic_suffix(app),
    )
  }
  println("MoonBit 46_asset_sidecar_resources probe passed")
}

///|
fn asset_sidecar_probe_expression() -> String {
  (
    #|;(async () => {
    #|  document.querySelector("#instant-left").value = "30";
    #|  document.querySelector("#instant-right").value = "12";
    #|  document.querySelector("#instant-form").requestSubmit();
    #|  await new Promise((resolve) => setTimeout(resolve, 50));
    #|  document.querySelector("#delayed-left").value = "9";
    #|  document.querySelector("#delayed-right").value = "8";
    #|  document.querySelector("#delayed-form").requestSubmit();
    #|  await new Promise((resolve) => setTimeout(resolve, 950));
    #|  const commandReply = await window.__MoonBit__.add.add({
    #|    left: 30,
    #|    right: 12,
    #|  });
    #|  const delayedReply = await window.__MoonBit__.add.addLater({
    #|    left: 20,
    #|    right: 22,
    #|  });
    #|  await window.__MoonBit__.add.reportProbe({
    #|    report: JSON.stringify({
    #|      ok: commandReply === 42 && delayedReply === 42,
    #|      source: "moonbit-e2e",
    #|    }),
    #|  });
    #|  const workerReply = await new Promise((resolve) => {
    #|    const worker = new Worker("/worker.js");
    #|    const timeout = setTimeout(() => {
    #|      worker.terminate();
    #|      resolve("timeout");
    #|    }, 3000);
    #|    worker.addEventListener("message", (event) => {
    #|      clearTimeout(timeout);
    #|      worker.terminate();
    #|      resolve(String(event.data));
    #|    }, { once: true });
    #|    worker.addEventListener("error", (event) => {
    #|      clearTimeout(timeout);
    #|      worker.terminate();
    #|      resolve(`error:${event.message}`);
    #|    }, { once: true });
    #|    worker.postMessage("ready");
    #|  });
    #|  return {
    #|    url: location.href,
    #|    pathname: location.pathname,
    #|    title: document.title,
    #|    has_bridge: typeof window.__MoonBit__?.core?.invokeOp === "function",
    #|    has_generated_proxy: typeof window.__MoonBit__?.add?.add === "function",
    #|    has_delayed_proxy: typeof window.__MoonBit__?.add?.addLater === "function",
    #|    has_report_proxy: typeof window.__MoonBit__?.add?.reportProbe === "function",
    #|    instant_result: document.querySelector("#instant-result")?.textContent || "",
    #|    delayed_result: document.querySelector("#delayed-result")?.textContent || "",
    #|    log_text: document.querySelector("#log")?.textContent || "",
    #|    css_loaded: getComputedStyle(document.documentElement)
    #|      .getPropertyValue("--accent")
    #|      .trim() !== "",
    #|    script_element_present: Boolean(document.querySelector('script[src="/app.js"]')),
    #|    worker_reply: workerReply,
    #|    command_reply: commandReply,
    #|    delayed_reply: delayedReply,
    #|  };
    #|})()
  )
}

///|
fn assert_asset_sidecar_probe(
  result : AssetSidecarScenarioProbe,
  value : Json,
) -> Unit raise {
  guard result.url == "https://proton.localhost/app.html#startup-fragment" &&
    result.pathname == "/app.html" &&
    result.title == "Asset Sidecar Resources" else {
    fail("asset sidecar page identity mismatch: " + value.stringify())
  }
  guard result.has_bridge &&
    result.has_generated_proxy &&
    result.has_delayed_proxy &&
    result.has_report_proxy else {
    fail("asset sidecar bridge was not installed: " + value.stringify())
  }
  guard result.instant_result == "42" && result.delayed_result == "17" else {
    fail("asset sidecar forms did not run commands: " + value.stringify())
  }
  guard result.css_loaded && result.script_element_present else {
    fail("asset sidecar resources were not loaded: " + value.stringify())
  }
  guard result.worker_reply == "worker:ready" else {
    fail("asset sidecar worker did not run: " + value.stringify())
  }
  guard result.command_reply == 42 && result.delayed_reply == 42 else {
    fail("asset sidecar command replies mismatch: " + value.stringify())
  }
}

///|
fn assert_asset_sidecar_native_log(path : String) -> Unit raise {
  for op in ["ext:add/add", "ext:add/addLater", "ext:add/reportProbe"] {
    guard count_native_log_entries(path, "bridge_enqueue", "op=" + op) > 0 else {
      fail("native log did not record " + op)
    }
  }
}
