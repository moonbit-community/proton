///|
struct DevTickReplyProbe {
  run_id : Int
  index : Int
  total : Int
  remaining : Int
} derive(FromJson, Eq, Debug)

///|
struct DevDoneReplyProbe {
  run_id : Int
  total : Int
} derive(FromJson, Eq, Debug)

///|
struct DevTickerReplyProbe {
  ticks : Array[DevTickReplyProbe]
  done : DevDoneReplyProbe
} derive(FromJson, Eq, Debug)

///|
struct DevEventProbe {
  kind : String
  run_id : Int
  index : Int?
  total : Int
} derive(FromJson, Eq, Debug)

///|
struct DevExtensionProbe {
  url : String
  origin : String
  title : String
  script_element_count : Int
  proton_script_element_count : Int
  has_bridge : Bool
  has_proxy : Bool
  has_event_proxy : Bool
  reply : DevTickerReplyProbe
  events : Array[DevEventProbe]
} derive(FromJson, Eq, Debug)

///|
struct DevExtensionReloadProbe {
  url : String
  origin : String
  title : String
  has_bridge : Bool
  has_proxy : Bool
  has_event_proxy : Bool
  navigation_type : String
  reply : DevTickerReplyProbe
  events : Array[DevEventProbe]
} derive(FromJson, Eq, Debug)

///|
async fn run_dev_extension_page_probe(
  app : SpawnedScenarioApp,
  target : String,
  frontend_url : String,
  output_root : String,
  timeout : Int,
) -> Unit {
  let page = connect_spawned_page(app, target, timeout)
  let mut page_open = true
  defer (if page_open { page.close() })
  ignore(page.send_schema_command("Runtime.enable"))
  wait_for_ready(page, dev_extension_ready_expression(), timeout)
  let value = evaluate_json(page, dev_extension_probe_expression(), true)
  let result : DevExtensionProbe = decode_probe(value, "dev extension")
  assert_dev_extension_probe(result, frontend_url, value)
  run_dev_extension_reload_probe(page, target, frontend_url, timeout)
  page_open = false
  run_dev_extension_non_proton_probe(target, output_root, timeout)
  assert_dev_extension_native_log(app.native_log_path)
  println("MoonBit 47_dev_extension_js dev probe passed")
}

///|
async fn run_dev_extension_production_page_probe(
  app : SpawnedScenarioApp,
  target : String,
  timeout : Int,
) -> Unit {
  let page = connect_spawned_page(app, target, timeout)
  defer page.close()
  ignore(page.send_schema_command("Runtime.enable"))
  wait_for_ready(page, dev_extension_ready_expression(), timeout) catch {
    error =>
      fail(error.to_string() + dev_extension_ready_diagnostic_suffix(page, app))
  }
  let value = evaluate_json(
    page,
    dev_extension_production_probe_expression(),
    true,
  )
  let result : DevExtensionReloadProbe = decode_probe(
    value, "dev extension production",
  )
  assert_dev_extension_production_probe(result, value)
  assert_dev_extension_native_log(app.native_log_path)
  println("MoonBit 47_dev_extension_js production probe passed")
}

///|
fn dev_extension_ready_expression() -> String {
  "Boolean(window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.ticker?.start && window.__MoonBit__?.ticker?.on && document.querySelector('#bridge-status')?.dataset.ready === 'true')"
}

///|
async fn dev_extension_ready_diagnostic_suffix(
  page : @client.CdpClient,
  app : SpawnedScenarioApp,
) -> String {
  let page_diagnostic = evaluate_json(
    page,
    dev_extension_ready_diagnostic_expression(),
    false,
  ) catch {
    error => Json("failed to collect page diagnostics: " + error.to_string())
  }
  "\nProduction page diagnostics:\n" +
  page_diagnostic.stringify() +
  app_diagnostic_suffix(app)
}

///|
fn dev_extension_ready_diagnostic_expression() -> String {
  (
    #|(() => {
    #|  try {
    #|    const moonbit = window.__MoonBit__;
    #|    const bridgeStatus = document.querySelector("#bridge-status");
    #|    const keys = (value) => value && typeof value === "object"
    #|      ? Object.keys(value).sort()
    #|      : [];
    #|    return {
    #|      url: location.href,
    #|      title: document.title,
    #|      ready_state: document.readyState,
    #|      bridge_status_text: bridgeStatus?.textContent || "",
    #|      bridge_status_dataset: bridgeStatus ? { ...bridgeStatus.dataset } : {},
    #|      moonbit_keys: keys(moonbit),
    #|      core_keys: keys(moonbit?.core),
    #|      ticker_keys: keys(moonbit?.ticker),
    #|      has_bridge: typeof moonbit?.core?.invokeOp === "function",
    #|      has_proxy: typeof moonbit?.ticker?.start === "function",
    #|      has_event_proxy: typeof moonbit?.ticker?.on === "function",
    #|      script_sources: Array.from(document.scripts, (script) => script.src || "[inline]"),
    #|      body_text: (document.body?.innerText || document.body?.textContent || "").slice(0, 4000),
    #|    };
    #|  } catch (error) {
    #|    return { diagnostic_error: String(error?.stack || error) };
    #|  }
    #|})()
  )
}

///|
fn dev_extension_probe_expression() -> String {
  (
    #|;(async () => {
    #|  window.__devExtensionProbe = [];
    #|  window.__MoonBit__.ticker.on("tick", (event) => {
    #|    window.__devExtensionProbe.push({
    #|      kind: "tick",
    #|      run_id: event.payload.run_id,
    #|      index: event.payload.index,
    #|      total: event.payload.total,
    #|    });
    #|  });
    #|  window.__MoonBit__.ticker.on("done", (event) => {
    #|    window.__devExtensionProbe.push({
    #|      kind: "done",
    #|      run_id: event.payload.run_id,
    #|      total: event.payload.total,
    #|    });
    #|  });
    #|  const reply = await window.__MoonBit__.ticker.start({
    #|    run_id: 9201,
    #|    count: 2,
    #|    interval_ms: 50,
    #|  });
    #|  return {
    #|    url: location.href,
    #|    origin: location.origin,
    #|    title: document.title,
    #|    script_element_count: document.scripts.length,
    #|    proton_script_element_count: Array.from(document.scripts).filter((script) => {
    #|      const text = (script.src || "") + "\n" + (script.textContent || "");
    #|      return /proton|moonbit/i.test(text);
    #|    }).length,
    #|    has_bridge: typeof window.__MoonBit__?.core?.invokeOp === "function",
    #|    has_proxy: typeof window.__MoonBit__?.ticker?.start === "function",
    #|    has_event_proxy: typeof window.__MoonBit__?.ticker?.on === "function",
    #|    reply,
    #|    events: window.__devExtensionProbe,
    #|  };
    #|})()
  )
}

///|
fn dev_extension_production_probe_expression() -> String {
  (
    #|;(async () => {
    #|  window.__productionExtensionProbe = [];
    #|  window.__MoonBit__.ticker.on("tick", (event) => {
    #|    window.__productionExtensionProbe.push({
    #|      kind: "tick",
    #|      run_id: event.payload.run_id,
    #|      index: event.payload.index,
    #|      total: event.payload.total,
    #|    });
    #|  });
    #|  window.__MoonBit__.ticker.on("done", (event) => {
    #|    window.__productionExtensionProbe.push({
    #|      kind: "done",
    #|      run_id: event.payload.run_id,
    #|      total: event.payload.total,
    #|    });
    #|  });
    #|  const reply = await window.__MoonBit__.ticker.start({
    #|    run_id: 9401,
    #|    count: 2,
    #|    interval_ms: 50,
    #|  });
    #|  return {
    #|    url: location.href,
    #|    origin: location.origin,
    #|    title: document.title,
    #|    has_bridge: typeof window.__MoonBit__?.core?.invokeOp === "function",
    #|    has_proxy: typeof window.__MoonBit__?.ticker?.start === "function",
    #|    has_event_proxy: typeof window.__MoonBit__?.ticker?.on === "function",
    #|    navigation_type: performance.getEntriesByType("navigation")[0]?.type || "",
    #|    reply,
    #|    events: window.__productionExtensionProbe,
    #|  };
    #|})()
  )
}

///|
async fn run_dev_extension_reload_probe(
  page : @client.CdpClient,
  target : String,
  frontend_url : String,
  timeout : Int,
) -> Unit {
  ignore(page.send_schema_command("Page.enable"))
  ignore(
    evaluate_json(
      page,
      (
        #|(() => {
        #|  const start = window.__MoonBit__?.ticker?.start;
        #|  if (typeof start === "function") {
        #|    void start({ run_id: 9300, count: 5, interval_ms: 50 }).catch(() => {});
        #|  }
        #|  return true;
        #|})()
      ),
      false,
    ),
  )
  ignore(page.send_cdp_command("Page.reload"))
  page.close()
  let reloaded_page = connect_page_matching_expression(
    target,
    frontend_url,
    true,
    (
      #|Boolean(
      #|  window.__MoonBit__?.ticker?.start &&
      #|  window.__MoonBit__?.ticker?.on &&
      #|  performance.getEntriesByType("navigation")[0]?.type === "reload"
      #|)
    ),
    "dev extension bridge after reload",
    timeout,
  )
  defer reloaded_page.close()
  let value = evaluate_json(
    reloaded_page,
    dev_extension_reload_probe_expression(),
    true,
  )
  let result : DevExtensionReloadProbe = decode_probe(
    value, "dev extension reload",
  )
  guard result.url.has_prefix(frontend_url) &&
    result.origin == frontend_url &&
    result.title == "Proton Dev Extension JS" &&
    result.navigation_type == "reload" else {
    fail("dev extension reload page identity mismatch: " + value.stringify())
  }
  assert_dev_extension_reply(result.reply, 9301, 1, value)
  assert_dev_extension_events(result.events, 9301, value)
}

///|
fn dev_extension_reload_probe_expression() -> String {
  (
    #|;(async () => {
    #|  window.__devExtensionReloadProbe = [];
    #|  window.__MoonBit__.ticker.on("tick", (event) => {
    #|    window.__devExtensionReloadProbe.push({
    #|      kind: "tick", run_id: event.payload.run_id,
    #|      index: event.payload.index, total: event.payload.total,
    #|    });
    #|  });
    #|  window.__MoonBit__.ticker.on("done", (event) => {
    #|    window.__devExtensionReloadProbe.push({
    #|      kind: "done", run_id: event.payload.run_id,
    #|      total: event.payload.total,
    #|    });
    #|  });
    #|  const reply = await window.__MoonBit__.ticker.start({
    #|    run_id: 9301, count: 1, interval_ms: 50,
    #|  });
    #|  await new Promise((resolve) => setTimeout(resolve, 350));
    #|  return {
    #|    url: location.href,
    #|    origin: location.origin,
    #|    title: document.title,
    #|    has_bridge: typeof window.__MoonBit__?.core?.invokeOp === "function",
    #|    has_proxy: typeof window.__MoonBit__?.ticker?.start === "function",
    #|    has_event_proxy: typeof window.__MoonBit__?.ticker?.on === "function",
    #|    navigation_type: performance.getEntriesByType("navigation")[0]?.type || "",
    #|    reply,
    #|    events: window.__devExtensionReloadProbe,
    #|  };
    #|})()
  )
}

///|
async fn run_dev_extension_non_proton_probe(
  target : String,
  output_root : String,
  timeout : Int,
) -> Unit {
  let file_path = join_path(output_root, "non-proton-dev-extension-probe.html")
  @mbfs.write_string_to_file(
    file_path, "<!doctype html><title>Non Proton File Probe</title><h1>file probe</h1>",
  ) catch {
    _ => fail("failed to write non-Proton dev probe: " + file_path)
  }
  defer (@mbfs.remove_file(file_path) catch { _ => () })
  let about = navigate_and_read_origin(target, "about:blank", timeout)
  let file = navigate_and_read_origin(target, file_url(file_path), timeout)
  let http_page = run_http_origin_probe(target, timeout)
  assert_non_proton_origin("about", about)
  assert_non_proton_origin("file", file)
  assert_non_proton_origin("http", http_page)
}

///|
fn assert_dev_extension_probe(
  result : DevExtensionProbe,
  frontend_url : String,
  value : Json,
) -> Unit raise {
  guard result.url.has_prefix(frontend_url) &&
    result.origin == frontend_url &&
    result.title == "Proton Dev Extension JS" else {
    fail("dev extension page identity mismatch: " + value.stringify())
  }
  guard result.script_element_count > 0 else {
    fail(
      "dev extension page did not load its frontend script: " +
      value.stringify(),
    )
  }
  guard result.proton_script_element_count == 0 else {
    fail("dev page contains a manual Proton script: " + value.stringify())
  }
  guard result.has_bridge && result.has_proxy && result.has_event_proxy else {
    fail("dev extension bridge was not installed: " + value.stringify())
  }
  assert_dev_extension_reply(result.reply, 9201, 2, value)
  let mut tick_count = 0
  let mut done_count = 0
  for event in result.events {
    if event.kind == "tick" {
      guard event.index == Some(tick_count + 1) &&
        event.run_id == 9201 &&
        event.total == 2 else {
        fail("dev extension tick event mismatch: " + value.stringify())
      }
      tick_count = tick_count + 1
    } else if event.kind == "done" {
      guard event.run_id == 9201 && event.total == 2 else {
        fail("dev extension done event mismatch: " + value.stringify())
      }
      done_count = done_count + 1
    } else {
      fail("dev extension returned an unknown event: " + value.stringify())
    }
  }
  guard tick_count == 2 && done_count == 1 else {
    fail("dev extension event count mismatch: " + value.stringify())
  }
}

///|
fn assert_dev_extension_reply(
  reply : DevTickerReplyProbe,
  run_id : Int,
  expected_total : Int,
  value : Json,
) -> Unit raise {
  guard reply.done.run_id == run_id && reply.done.total == expected_total else {
    fail("dev extension reply mismatch: " + value.stringify())
  }
  guard reply.ticks.length() == expected_total else {
    fail("dev extension reply tick count mismatch: " + value.stringify())
  }
  for index in 1..<=expected_total {
    let tick = reply.ticks[index - 1]
    guard tick.run_id == run_id &&
      tick.index == index &&
      tick.total == expected_total &&
      tick.remaining == expected_total - index else {
      fail("dev extension reply tick mismatch: " + value.stringify())
    }
  }
}

///|
fn assert_dev_extension_events(
  events : Array[DevEventProbe],
  run_id : Int,
  value : Json,
) -> Unit raise {
  let mut done_count = 0
  let mut tick_count = 0
  for event in events {
    guard event.run_id == run_id else {
      fail("dev extension reload delivered a stale event: " + value.stringify())
    }
    if event.kind == "tick" {
      guard event.index == Some(tick_count + 1) && event.total == 1 else {
        fail("dev extension reload tick mismatch: " + value.stringify())
      }
      tick_count = tick_count + 1
    } else if event.kind == "done" {
      guard event.total == 1 else {
        fail("dev extension reload done mismatch: " + value.stringify())
      }
      done_count = done_count + 1
    } else {
      fail(
        "dev extension reload returned an unknown event: " + value.stringify(),
      )
    }
  }
  guard tick_count == 1 && done_count == 1 else {
    fail("dev extension reload event count mismatch: " + value.stringify())
  }
}

///|
fn assert_dev_extension_production_probe(
  result : DevExtensionReloadProbe,
  value : Json,
) -> Unit raise {
  guard result.url.has_prefix("https://proton.localhost/") &&
    result.title == "Proton Dev Extension JS" else {
    fail(
      "production dev extension page identity mismatch: " + value.stringify(),
    )
  }
  guard result.has_bridge && result.has_proxy && result.has_event_proxy else {
    fail(
      "production dev extension bridge was not installed: " + value.stringify(),
    )
  }
  assert_dev_extension_reply(result.reply, 9401, 2, value)
  let mut tick_count = 0
  let mut done_count = 0
  for event in result.events {
    if event.kind == "tick" {
      guard event.index == Some(tick_count + 1) &&
        event.run_id == 9401 &&
        event.total == 2 else {
        fail(
          "production dev extension tick event mismatch: " + value.stringify(),
        )
      }
      tick_count = tick_count + 1
    } else if event.kind == "done" {
      guard event.run_id == 9401 && event.total == 2 else {
        fail(
          "production dev extension done event mismatch: " + value.stringify(),
        )
      }
      done_count = done_count + 1
    } else {
      fail(
        "production dev extension returned an unknown event: " +
        value.stringify(),
      )
    }
  }
  guard tick_count == 2 && done_count == 1 else {
    fail("production dev extension event count mismatch: " + value.stringify())
  }
}

///|
fn assert_dev_extension_native_log(path : String) -> Unit raise {
  guard count_native_log_entries(path, "bridge_enqueue", "op=ext:ticker/start") >
    0 else {
    fail("native log did not record ext:ticker/start for dev extension")
  }
}
