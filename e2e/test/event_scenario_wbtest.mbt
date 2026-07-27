///|
struct EventTickReplyProbe {
  run_id : Int
  index : Int
  total : Int
  remaining : Int
} derive(FromJson, Eq, Debug)

///|
struct EventDoneReplyProbe {
  run_id : Int
  total : Int
} derive(FromJson, Eq, Debug)

///|
struct EventTickerReplyProbe {
  ticks : Array[EventTickReplyProbe]
  done : EventDoneReplyProbe
} derive(FromJson, Eq, Debug)

///|
struct EventCaptureProbe {
  kind : String
  run_id : Int
  index : Int?
  total : Int
} derive(FromJson, Eq, Debug)

///|
struct EventScenarioProbe {
  url : String
  title : String
  has_bridge : Bool
  has_proxy : Bool
  has_event_proxy : Bool
  reply : EventTickerReplyProbe
  events : Array[EventCaptureProbe]
} derive(FromJson, Eq, Debug)

///|
struct EventReloadScenarioProbe {
  url : String
  title : String
  has_bridge : Bool
  has_proxy : Bool
  has_event_proxy : Bool
  navigation_type : String
  reply : EventTickerReplyProbe
  events : Array[EventCaptureProbe]
} derive(FromJson, Eq, Debug)

///|
async fn run_event_scenario_page_probe(
  app : SpawnedScenarioApp,
  target : String,
  timeout : Int,
) -> Unit {
  let page = connect_spawned_page(app, target, timeout)
  defer page.close()
  ignore(page.send_schema_command("Runtime.enable"))
  wait_for_cdp_expression(
    page, "Boolean(window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.ticker?.start && window.__MoonBit__?.ticker?.on)",
    "event broadcast bridge", timeout,
  )
  let value = evaluate_json(
    page,
    (
      #|;(async () => {
      #|  window.__eventProbe = [];
      #|  window.__MoonBit__.ticker.on("tick", (event) => {
      #|    window.__eventProbe.push({
      #|      kind: "tick",
      #|      run_id: event.payload.run_id,
      #|      index: event.payload.index,
      #|      total: event.payload.total,
      #|    });
      #|  });
      #|  window.__MoonBit__.ticker.on("done", (event) => {
      #|    window.__eventProbe.push({
      #|      kind: "done",
      #|      run_id: event.payload.run_id,
      #|      total: event.payload.total,
      #|    });
      #|  });
      #|  const reply = await window.__MoonBit__.ticker.start({
      #|    run_id: 9001,
      #|    count: 3,
      #|    interval_ms: 100,
      #|  });
      #|  return {
      #|    url: location.href,
      #|    title: document.title,
      #|    has_bridge: typeof window.__MoonBit__?.core?.invokeOp === "function",
      #|    has_proxy: typeof window.__MoonBit__?.ticker?.start === "function",
      #|    has_event_proxy: typeof window.__MoonBit__?.ticker?.on === "function",
      #|    reply,
      #|    events: window.__eventProbe,
      #|  };
      #|})()
    ),
    true,
  )
  let result : EventScenarioProbe = decode_probe(value, "event broadcast")
  assert_event_scenario_probe(result, value)
  run_event_reload_scenario_probe(page, timeout)
  assert_event_scenario_native_log(app.native_log_path)
  println("MoonBit 40_event_broadcast event/reload probe passed")
}

///|
fn assert_event_scenario_probe(
  result : EventScenarioProbe,
  value : Json,
) -> Unit raise {
  guard result.url == "proton://app/" &&
    result.title == "MoonBit Event Broadcast" else {
    fail("event broadcast page identity mismatch: " + value.stringify())
  }
  guard result.has_bridge && result.has_proxy && result.has_event_proxy else {
    fail("event broadcast bridge was not installed: " + value.stringify())
  }
  guard result.reply.done.run_id == 9001 && result.reply.done.total == 3 else {
    fail("event broadcast done reply mismatch: " + value.stringify())
  }
  guard result.reply.ticks.length() == 3 else {
    fail(
      "event broadcast reply did not contain three ticks: " + value.stringify(),
    )
  }
  for index, tick in result.reply.ticks {
    guard tick.run_id == 9001 &&
      tick.index == index + 1 &&
      tick.total == 3 &&
      tick.remaining == 2 - index else {
      fail("event broadcast reply tick mismatch: " + value.stringify())
    }
  }
  let mut tick_events = 0
  let mut done_events = 0
  for event in result.events {
    if event.kind == "tick" {
      guard event.run_id == 9001 &&
        event.index == Some(tick_events + 1) &&
        event.total == 3 else {
        fail("event broadcast tick event mismatch: " + value.stringify())
      }
      tick_events = tick_events + 1
    } else if event.kind == "done" {
      guard event.run_id == 9001 && event.total == 3 else {
        fail("event broadcast done event mismatch: " + value.stringify())
      }
      done_events = done_events + 1
    }
  }
  guard tick_events == 3 && done_events == 1 else {
    fail("event broadcast event count mismatch: " + value.stringify())
  }
}

///|
async fn run_event_reload_scenario_probe(
  page : @client.CdpClient,
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
        #|    void start({
        #|      run_id: 9100,
        #|      count: 5,
        #|      interval_ms: 100,
        #|    }).catch(() => {});
        #|  }
        #|  location.reload();
        #|  return true;
        #|})()
      ),
      false,
    ),
  )
  wait_for_cdp_expression(
    page,
    (
      #|Boolean(
      #|  window.__MoonBit__?.ticker?.start &&
      #|  window.__MoonBit__?.ticker?.on &&
      #|  performance.getEntriesByType("navigation")[0]?.type === "reload"
      #|)
    ),
    "event bridge after reload",
    timeout,
  )
  let value = evaluate_json(
    page,
    (
      #|;(async () => {
      #|  window.__eventReloadProbe = [];
      #|  window.__MoonBit__.ticker.on("tick", (event) => {
      #|    window.__eventReloadProbe.push({
      #|      kind: "tick",
      #|      run_id: event.payload.run_id,
      #|      index: event.payload.index,
      #|      total: event.payload.total,
      #|    });
      #|  });
      #|  window.__MoonBit__.ticker.on("done", (event) => {
      #|    window.__eventReloadProbe.push({
      #|      kind: "done",
      #|      run_id: event.payload.run_id,
      #|      total: event.payload.total,
      #|    });
      #|  });
      #|  const reply = await window.__MoonBit__.ticker.start({
      #|    run_id: 9101,
      #|    count: 1,
      #|    interval_ms: 100,
      #|  });
      #|  await new Promise((resolve) => setTimeout(resolve, 700));
      #|  return {
      #|    url: location.href,
      #|    title: document.title,
      #|    has_bridge: typeof window.__MoonBit__?.core?.invokeOp === "function",
      #|    has_proxy: typeof window.__MoonBit__?.ticker?.start === "function",
      #|    has_event_proxy: typeof window.__MoonBit__?.ticker?.on === "function",
      #|    navigation_type: performance.getEntriesByType("navigation")[0]?.type || "",
      #|    reply,
      #|    events: window.__eventReloadProbe,
      #|  };
      #|})()
    ),
    true,
  )
  let result : EventReloadScenarioProbe = decode_probe(
    value, "event broadcast reload",
  )
  guard result.url == "proton://app/" &&
    result.title == "MoonBit Event Broadcast" &&
    result.navigation_type == "reload" else {
    fail("event reload page identity mismatch: " + value.stringify())
  }
  guard result.has_bridge && result.has_proxy && result.has_event_proxy else {
    fail("event bridge was not reinstalled after reload: " + value.stringify())
  }
  guard result.reply.done.run_id == 9101 && result.reply.done.total == 1 else {
    fail("event reload reply mismatch: " + value.stringify())
  }
  let mut current_done = 0
  for event in result.events {
    guard event.run_id != 9100 else {
      fail(
        "event reload delivered a stale pre-reload event: " + value.stringify(),
      )
    }
    if event.kind == "done" && event.run_id == 9101 && event.total == 1 {
      current_done = current_done + 1
    }
  }
  guard current_done == 1 else {
    fail(
      "event reload did not deliver the current done event: " +
      value.stringify(),
    )
  }
}

///|
fn assert_event_scenario_native_log(path : String) -> Unit raise {
  guard count_native_log_entries(path, "bridge_enqueue", "op=ext:ticker/start") >
    0 else {
    fail("native log did not record ext:ticker/start")
  }
}
