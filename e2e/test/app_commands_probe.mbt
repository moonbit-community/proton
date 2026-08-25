///|
struct BridgeContractProbe {
  has_api : Bool
  has_invoke_op : Bool
  has_ready_property : Bool
} derive(ToJson, FromJson, Eq, Debug)

///|
pub extend BridgeContractProbe with Eq::{not_equal, equal}

///|
pub extend BridgeContractProbe with Debug::{to_repr}

///|
pub extend BridgeContractProbe with ToJson::{to_json}

///|
pub extend BridgeContractProbe with FromJson::{from_json}

///|
struct AppCommandsProbeResult {
  url : String
  title : String
  has_bridge : Bool
  ping_message : String
  ping_source : String
  sum_total : Int
  sum_source : String
  string_result : String
  unknown_rejected : Bool
  unknown_message : String
  fail_rejected : Bool
  fail_message : String
  large_payload_rejected : Bool
  large_payload_message : String
} derive(ToJson, FromJson, Eq, Debug)

///|
pub extend AppCommandsProbeResult with Eq::{not_equal, equal}

///|
pub extend AppCommandsProbeResult with Debug::{to_repr}

///|
pub extend AppCommandsProbeResult with ToJson::{to_json}

///|
pub extend AppCommandsProbeResult with FromJson::{from_json}

///|
struct QueueFullProbeResult {
  requested : Int
  fulfilled : Int
  rejected : Int
  full_rejected : Bool
  first_rejected_message : String
} derive(ToJson, FromJson, Eq, Debug)

///|
pub extend QueueFullProbeResult with Eq::{not_equal, equal}

///|
pub extend QueueFullProbeResult with Debug::{to_repr}

///|
pub extend QueueFullProbeResult with ToJson::{to_json}

///|
pub extend QueueFullProbeResult with FromJson::{from_json}

///|
struct ReloadProbeResult {
  url : String
  title : String
  has_bridge : Bool
  navigation_type : String
  ping_message : String
} derive(ToJson, FromJson, Eq, Debug)

///|
pub extend ReloadProbeResult with Eq::{not_equal, equal}

///|
pub extend ReloadProbeResult with Debug::{to_repr}

///|
pub extend ReloadProbeResult with ToJson::{to_json}

///|
pub extend ReloadProbeResult with FromJson::{from_json}

///|
struct OriginProbeResult {
  url : String
  title : String
  has_bridge : Bool
  has_native_invoke : Bool
} derive(ToJson, FromJson, Eq, Debug)

///|
pub extend OriginProbeResult with Eq::{not_equal, equal}

///|
pub extend OriginProbeResult with Debug::{to_repr}

///|
pub extend OriginProbeResult with ToJson::{to_json}

///|
pub extend OriginProbeResult with FromJson::{from_json}

///|
struct ScreenshotProbeResult {
  bytes : Int
  width : Int
  height : Int
} derive(Eq, Debug)

///|
pub extend ScreenshotProbeResult with Eq::{not_equal, equal}

///|
pub extend ScreenshotProbeResult with Debug::{to_repr}

///|
async fn run_app_commands_full_probe(
  tasks : @async.TaskGroup[Unit],
  output_root : String,
  target : String,
  timeout : Int,
) -> Unit {
  let page = @page.Page::connect(
    tasks,
    cdp_target_from(target),
    timeout_ms=timeout,
  )
  wait_for_ready(page, scenario_ready_expression("41_app_commands"), timeout)
  assert_bridge_contract(page)
  let screenshot = capture_headless_screenshot(page)
  assert_app_commands_probe(page)
  let queue = run_queue_full_probe(page)
  run_reload_probe(page, timeout)
  page.close()
  run_non_proton_probe(tasks, target, output_root, timeout)
  println(
    "MoonBit 41_app_commands full probe passed: screenshot=" +
    screenshot.width.to_string() +
    "x" +
    screenshot.height.to_string() +
    " bytes=" +
    screenshot.bytes.to_string() +
    " queue=" +
    queue.fulfilled.to_string() +
    "/" +
    queue.rejected.to_string(),
  )
}

///|
async fn assert_bridge_contract(page : @page.Page) -> Unit {
  let value = evaluate_json(
    page,
    (
      #|(() => {
      #|  const api = window.__MoonBit__;
      #|  return {
      #|    has_api: Boolean(api),
      #|    has_invoke_op: typeof api?.core?.invokeOp === "function",
      #|    has_ready_property: Object.prototype.hasOwnProperty.call(api || {}, "ready"),
      #|  };
      #|})()
    ),
    false,
  )
  let result : BridgeContractProbe = decode_probe(value, "bridge contract")
  guard result.has_api && result.has_invoke_op && !result.has_ready_property else {
    fail("synchronous bridge contract failed: " + value.stringify())
  }
}

///|
async fn capture_headless_screenshot(
  page : @page.Page,
) -> ScreenshotProbeResult {
  let encoded = page.capture_png()
  let png = @base64.decode(encoded) catch {
    _ => fail("Page.captureScreenshot returned invalid base64")
  }
  let signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
  guard png.length() >= 24 else {
    fail("headless screenshot PNG is too short: " + png.length().to_string())
  }
  for index, expected in signature {
    guard png[index].to_int() == expected else {
      fail("headless screenshot has an invalid PNG signature")
    }
  }
  let width = png_u32_be(png, 16)
  let height = png_u32_be(png, 20)
  guard width > 1 && height > 1 else {
    fail(
      "headless screenshot has invalid dimensions: " +
      width.to_string() +
      "x" +
      height.to_string(),
    )
  }
  ScreenshotProbeResult::{ bytes: png.length(), width, height }
}

///|
fn png_u32_be(bytes : Bytes, offset : Int) -> Int {
  (bytes[offset].to_int() << 24) |
  (bytes[offset + 1].to_int() << 16) |
  (bytes[offset + 2].to_int() << 8) |
  bytes[offset + 3].to_int()
}

///|
async fn assert_app_commands_probe(page : @page.Page) -> Unit {
  let value = evaluate_json(
    page,
    (
      #|;(async () => {
      #|  const invoke = window.__MoonBit__?.core?.invokeOp;
      #|  const ping = await invoke("ext:appCommands/ping", { name: "proton" });
      #|  const sum = await invoke("ext:appCommands/slowAdd", {
      #|    left: 20,
      #|    right: 22,
      #|    delay_ms: 50,
      #|  });
      #|  const stringResult = await invoke("ext:appCommands/stringResult", {});
      #|  let unknown_rejected = false;
      #|  let unknown_message = "";
      #|  try {
      #|    await invoke("ext:appCommands/unknown", {});
      #|  } catch (error) {
      #|    unknown_rejected = true;
      #|    unknown_message = String(error && error.message ? error.message : error);
      #|  }
      #|  let fail_rejected = false;
      #|  let fail_message = "";
      #|  try {
      #|    await invoke("ext:appCommands/fail", {
      #|      message: "Failure crossed command boundary",
      #|    });
      #|  } catch (error) {
      #|    fail_rejected = true;
      #|    fail_message = String(error && error.message ? error.message : error);
      #|  }
      #|  let large_payload_rejected = false;
      #|  let large_payload_message = "";
      #|  try {
      #|    await invoke("ext:appCommands/ping", {
      #|      oversized: "x".repeat(1048577),
      #|    });
      #|  } catch (error) {
      #|    large_payload_rejected = true;
      #|    large_payload_message = String(error && error.message ? error.message : error);
      #|  }
      #|  return {
      #|    url: location.href,
      #|    title: document.title,
      #|    has_bridge: typeof invoke === "function",
      #|    ping_message: ping?.message || "",
      #|    ping_source: ping?.source || "",
      #|    sum_total: sum?.total || 0,
      #|    sum_source: sum?.source || "",
      #|    string_result: stringResult,
      #|    unknown_rejected,
      #|    unknown_message,
      #|    fail_rejected,
      #|    fail_message,
      #|    large_payload_rejected,
      #|    large_payload_message,
      #|  };
      #|})()
    ),
    true,
  )
  let result : AppCommandsProbeResult = decode_probe(value, "app commands")
  guard result.url == "https://proton.localhost/" else {
    fail("unexpected app commands URL: " + value.stringify())
  }
  guard result.title == "MoonBit App Commands" && result.has_bridge else {
    fail("app commands bridge was not installed: " + value.stringify())
  }
  guard result.ping_message == "Hello proton from the app command layer" &&
    result.ping_source == "commands" else {
    fail("unexpected ping result: " + value.stringify())
  }
  guard result.sum_total == 42 && result.sum_source == "commands" else {
    fail("unexpected slowAdd result: " + value.stringify())
  }
  guard result.string_result == "Cancelled" else {
    fail("unexpected string result: " + value.stringify())
  }
  guard result.unknown_rejected &&
    result.unknown_message.contains("bridge op is not registered") else {
    fail("unknown op did not reject correctly: " + value.stringify())
  }
  guard result.fail_rejected &&
    result.fail_message.contains("op ext:appCommands/fail failed") else {
    fail("failing command did not reject correctly: " + value.stringify())
  }
  guard result.large_payload_rejected &&
    (
      result.large_payload_message.contains("invalid bridge request") ||
      result.large_payload_message.contains("bridge payload is too large")
    ) else {
    fail("oversized payload did not reject correctly: " + value.stringify())
  }
}

///|
async fn run_queue_full_probe(page : @page.Page) -> QueueFullProbeResult {
  let value = evaluate_json(
    page,
    (
      #|;(async () => {
      #|  const invoke = window.__MoonBit__?.core?.invokeOp;
      #|  const requested = 320;
      #|  const calls = Array.from({ length: requested }, (_, index) =>
      #|    invoke("ext:appCommands/slowAdd", {
      #|      left: index,
      #|      right: 1,
      #|      delay_ms: 3500,
      #|    })
      #|  );
      #|  const settled = await Promise.allSettled(calls);
      #|  const rejected_messages = settled
      #|    .filter((item) => item.status === "rejected")
      #|    .map((item) => String(item.reason && item.reason.message ? item.reason.message : item.reason));
      #|  return {
      #|    requested,
      #|    fulfilled: settled.filter((item) => item.status === "fulfilled").length,
      #|    rejected: rejected_messages.length,
      #|    full_rejected: rejected_messages.some((message) =>
      #|      message.includes("bridge request queue is full")
      #|    ),
      #|    first_rejected_message: rejected_messages[0] || "",
      #|  };
      #|})()
    ),
    true,
  )
  let result : QueueFullProbeResult = decode_probe(value, "queue full")
  guard result.requested == 320 &&
    result.fulfilled > 0 &&
    result.rejected > 0 &&
    result.fulfilled + result.rejected == result.requested &&
    result.full_rejected &&
    result.first_rejected_message.contains("bridge request queue is full") else {
    fail("queue full probe failed: " + value.stringify())
  }
  result
}

///|
async fn run_reload_probe(page : @page.Page, timeout : Int) -> Unit {
  ignore(
    evaluate_json(
      page,
      (
        #|(() => {
        #|  const invoke = window.__MoonBit__?.core?.invokeOp;
        #|  if (typeof invoke === "function") {
        #|    void invoke("ext:appCommands/slowAdd", {
        #|      left: 1,
        #|      right: 2,
        #|      delay_ms: 1000,
        #|    }).catch(() => {});
        #|  }
        #|  return true;
        #|})()
      ),
      false,
    ),
  )
  reload_page_and_wait(
    page,
    (
      #|Boolean(
      #|  window.__MoonBit__?.core?.invokeOp &&
      #|  performance.getEntriesByType("navigation")[0]?.type === "reload"
      #|)
    ),
    "bridge after reload",
    timeout,
  )
  let value = evaluate_json(
    page,
    (
      #|;(async () => {
      #|  const invoke = window.__MoonBit__?.core?.invokeOp;
      #|  const ping = await invoke("ext:appCommands/ping", { name: "reload" });
      #|  return {
      #|    url: location.href,
      #|    title: document.title,
      #|    has_bridge: typeof invoke === "function",
      #|    navigation_type: performance.getEntriesByType("navigation")[0]?.type || "",
      #|    ping_message: ping?.message || "",
      #|  };
      #|})()
    ),
    true,
  )
  let result : ReloadProbeResult = decode_probe(value, "reload")
  guard result.url == "https://proton.localhost/" &&
    result.title == "MoonBit App Commands" &&
    result.has_bridge &&
    result.navigation_type == "reload" &&
    result.ping_message == "Hello reload from the app command layer" else {
    fail("reload probe failed: " + value.stringify())
  }
}

///|
async fn run_non_proton_probe(
  tasks : @async.TaskGroup[Unit],
  target : String,
  output_root : String,
  timeout : Int,
) -> Unit {
  let file_path = join_path(output_root, "non-proton-moonbit-probe.html")
  @mbfs.write_string_to_file(
    file_path, "<!doctype html><title>Non Proton File Probe</title><h1>file probe</h1>",
  ) catch {
    _ => fail("failed to write non-Proton file probe: " + file_path)
  }
  defer (@mbfs.remove_file(file_path) catch { _ => () })
  let about = navigate_and_read_origin(tasks, target, "about:blank", timeout)
  let file = navigate_and_read_origin(
    tasks,
    target,
    file_url(file_path),
    timeout,
  )
  let http_page = run_http_origin_probe(target, timeout)
  assert_non_proton_origin("about", about)
  assert_non_proton_origin("file", file)
  assert_non_proton_origin("http", http_page)
  let proton_page = navigate_page_and_connect(
    tasks, target, "https://proton.localhost/", timeout,
  )
  wait_for_ready(
    proton_page,
    scenario_ready_expression("41_app_commands"),
    timeout,
  )
}

///|
async fn run_http_origin_probe(
  target : String,
  timeout : Int,
) -> OriginProbeResult {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"), headers={
      "Content-Type": "text/html; charset=utf-8",
    })
    defer server.close()
    let server_task = group.spawn(no_wait=true, () => {
      let (connection, _) = server.accept()
      defer connection.close()
      ignore(connection.read_request())
      connection.send_response(200, "OK")
      connection.write_string(
        "<!doctype html><title>Non Proton HTTP Probe</title><h1>http probe</h1>",
      )
      connection.end_response()
    })
    let result = navigate_and_read_origin(
      group,
      target,
      "http://127.0.0.1:" + server.addr.port().to_string() + "/probe.html",
      timeout,
    )
    server_task.wait()
    result
  })
}

///|
async fn[X] navigate_and_read_origin(
  tasks : @async.TaskGroup[X],
  target : String,
  url : String,
  timeout : Int,
) -> OriginProbeResult {
  let page = navigate_page_and_connect(tasks, target, url, timeout)
  let value = evaluate_json(
    page,
    (
      #|(() => ({
      #|  url: location.href,
      #|  title: document.title,
      #|  has_bridge: Boolean(window.__MoonBit__?.core?.invokeOp),
      #|  has_native_invoke: typeof window.__protonNativeInvokeOp === "function",
      #|}))()
    ),
    false,
  )
  decode_probe(value, "origin " + url)
}

///|
async fn[X] navigate_page_and_connect(
  tasks : @async.TaskGroup[X],
  target : String,
  url : String,
  timeout : Int,
) -> @page.Page {
  let current = @page.Page::connect(
    tasks,
    cdp_target_from(target),
    timeout_ms=timeout,
  )
  ignore(current.navigate(url))
  current.close()
  connect_page_matching_expression(
    tasks,
    target,
    url,
    false,
    "document.readyState !== 'loading'",
    "navigation to " + url,
    timeout,
  )
}

///|
async fn[X] connect_page_matching_expression(
  tasks : @async.TaskGroup[X],
  target : String,
  url : String,
  allow_prefix : Bool,
  expression : String,
  description : String,
  timeout : Int,
) -> @page.Page {
  let mut elapsed = 0
  while elapsed <= timeout {
    let targets = discover_targets_for_poll(cdp_target_from(target))
    for info in targets {
      if info.target_type == "page" &&
        (
          page_url_matches(info.url, url) ||
          (allow_prefix && info.url.has_prefix(url))
        ) {
        let page = Some(
          @page.Page::connect(
            tasks,
            cdp_target_from(target),
            target_id=info.target_id,
            timeout_ms=cdp_start_poll_timeout_ms,
          ),
        ) catch {
          _ => None
        }
        match page {
          Some(page) => {
            let ready = Some(
              run_e2e_operation_with_timeout(
                cdp_start_poll_timeout_ms,
                description,
                () => evaluate_bool(page, expression, false),
              ),
            ) catch {
              _ => None
            }
            if ready == Some(true) {
              return page
            }
            page.close()
          }
          None => ()
        }
      }
    }
    @async.sleep(100)
    elapsed = elapsed + 100
  }
  fail("timed out waiting for " + description)
}

///|
fn page_url_matches(actual : String, expected : String) -> Bool {
  if @path.sep == '\\' && expected.to_lower().has_prefix("file:") {
    actual.to_lower() == expected.to_lower()
  } else {
    actual == expected
  }
}

///|
async fn wait_for_cdp_expression(
  page : @page.Page,
  expression : String,
  description : String,
  timeout : Int,
) -> Unit {
  ignore(
    run_e2e_operation_with_timeout(timeout, description, () => {
      page.wait_until(expression)
    }),
  )
}

///|
fn assert_non_proton_origin(
  name : String,
  result : OriginProbeResult,
) -> Unit raise {
  guard !result.has_bridge && !result.has_native_invoke else {
    fail(
      name +
      " page unexpectedly exposed the Proton bridge: " +
      result.to_json().stringify(),
    )
  }
}

///|
fn file_url(path : String) -> String {
  let escaped = path
    .replace_all(old="%", new="%25")
    .replace_all(old=" ", new="%20")
    .replace_all(old="#", new="%23")
    .replace_all(old="?", new="%3F")
    .replace_all(old="\\", new="/")
  if @path.sep == '\\' {
    "file:///" + escaped
  } else {
    "file://" + escaped
  }
}

///|
fn parse_log_int(value : StringView) -> Int? {
  Some(@string.parse_int(value)) catch {
    _ => None
  }
}

///|
fn[X : FromJson] decode_probe(value : Json, label : String) -> X raise {
  @json.from_json(value) catch {
    error =>
      fail(
        label +
        " probe returned an invalid value: " +
        error.to_string() +
        "\n" +
        value.stringify(),
      )
  }
}
