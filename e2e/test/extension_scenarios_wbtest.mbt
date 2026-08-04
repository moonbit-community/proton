///|
struct AsyncAddScenarioProbe {
  url : String
  title : String
  has_bridge : Bool
  has_proxy : Bool
  reply : Int
} derive(FromJson, Eq, Debug)

///|
struct SyncDoubleScenarioReply {
  value : Int
  doubled : Int
  source : String
} derive(FromJson, Eq, Debug)

///|
struct AsyncSumScenarioReply {
  total : Int
  waited_ms : Int
  source : String
} derive(FromJson, Eq, Debug)

///|
struct SyncAsyncScenarioProbe {
  url : String
  title : String
  has_bridge : Bool
  has_math_proxy : Bool
  has_add_proxy : Bool
  doubled : SyncDoubleScenarioReply
  added : AsyncSumScenarioReply
} derive(FromJson, Eq, Debug)

///|
struct AttributeEventProbe {
  name : String
  extension : String
  total : Int
} derive(FromJson, Eq, Debug)

///|
struct AttributeReplyProbe {
  total : Int
  waited_ms : Int
} derive(FromJson, Eq, Debug)

///|
struct AttributeScenarioProbe {
  url : String
  title : String
  has_bridge : Bool
  has_generated_proxy : Bool
  has_event_api : Bool
  reply : AttributeReplyProbe
  events : Array[AttributeEventProbe]
} derive(FromJson, Eq, Debug)

///|
async fn run_extension_scenario_page_probe(
  app : SpawnedScenarioApp,
  target : String,
  name : String,
  timeout : Int,
  native_log_path : String,
) -> Unit {
  let page = connect_spawned_page(app, target, timeout)
  defer page.close()
  ignore(page.send_schema_command("Runtime.enable"))
  wait_for_ready(page, scenario_ready_expression(name), timeout)
  let bridge_expression = match name {
    "38_async_extension_add" =>
      "Boolean(window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.add?.slowAdd)"
    "39_sync_async_extensions" =>
      "Boolean(window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.math?.double && window.__MoonBit__?.add?.slowAdd)"
    "42_attribute_codegen_commands" =>
      "Boolean(window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.add?.slowAdd && window.__MoonBit__?.events?.on)"
    _ => fail("unsupported extension scenario: " + name)
  }
  wait_for_cdp_expression(
    page,
    bridge_expression,
    "bridge for " + name,
    timeout,
  )
  run_extension_scenario_probe(name, page, native_log_path)
}

///|
async fn run_extension_scenario_probe(
  name : String,
  page : @client.CdpClient,
  native_log_path : String,
) -> Unit {
  match name {
    "38_async_extension_add" => run_async_add_scenario_probe(page)
    "39_sync_async_extensions" => run_sync_async_scenario_probe(page)
    "42_attribute_codegen_commands" => run_attribute_scenario_probe(page)
    _ => fail("unsupported extension scenario: " + name)
  }
  assert_extension_scenario_native_log(name, native_log_path)
}

///|
async fn run_async_add_scenario_probe(page : @client.CdpClient) -> Unit {
  let value = evaluate_json(
    page,
    (
      #|;(async () => {
      #|  const invoke = window.__MoonBit__?.core?.invokeOp;
      #|  const reply = await window.__MoonBit__.add.slowAdd({
      #|    left: 2,
      #|    right: 3,
      #|  });
      #|  return {
      #|    url: location.href,
      #|    title: document.title,
      #|    has_bridge: typeof invoke === "function",
      #|    has_proxy: typeof window.__MoonBit__?.add?.slowAdd === "function",
      #|    reply,
      #|  };
      #|})()
    ),
    true,
  )
  let result : AsyncAddScenarioProbe = decode_probe(value, "async add")
  guard result.url == "https://proton.localhost/" &&
    result.title == "MoonBit Async Add Extension" else {
    fail("async add page identity mismatch: " + value.stringify())
  }
  guard result.has_bridge && result.has_proxy && result.reply == 5 else {
    fail("async add proxy probe failed: " + value.stringify())
  }
}

///|
async fn run_sync_async_scenario_probe(page : @client.CdpClient) -> Unit {
  let value = evaluate_json(
    page,
    (
      #|;(async () => {
      #|  const invoke = window.__MoonBit__?.core?.invokeOp;
      #|  const doubled = await window.__MoonBit__.math.double({ value: 21 });
      #|  const added = await window.__MoonBit__.add.slowAdd({
      #|    left: 20,
      #|    right: 22,
      #|    delay_ms: 10,
      #|  });
      #|  return {
      #|    url: location.href,
      #|    title: document.title,
      #|    has_bridge: typeof invoke === "function",
      #|    has_math_proxy: typeof window.__MoonBit__?.math?.double === "function",
      #|    has_add_proxy: typeof window.__MoonBit__?.add?.slowAdd === "function",
      #|    doubled,
      #|    added,
      #|  };
      #|})()
    ),
    true,
  )
  let result : SyncAsyncScenarioProbe = decode_probe(value, "sync/async")
  guard result.url == "https://proton.localhost/" &&
    result.title == "MoonBit Sync + Async Extensions" else {
    fail("sync/async page identity mismatch: " + value.stringify())
  }
  guard result.has_bridge && result.has_math_proxy && result.has_add_proxy else {
    fail("sync/async proxy bridge was not installed: " + value.stringify())
  }
  guard result.doubled.value == 21 &&
    result.doubled.doubled == 42 &&
    result.doubled.source == "sync command extension" else {
    fail("sync double result mismatch: " + value.stringify())
  }
  guard result.added.total == 42 &&
    result.added.waited_ms == 10 &&
    result.added.source == "async command extension" else {
    fail("async add result mismatch: " + value.stringify())
  }
}

///|
async fn run_attribute_scenario_probe(page : @client.CdpClient) -> Unit {
  let value = evaluate_json(
    page,
    (
      #|;(async () => {
      #|  const invoke = window.__MoonBit__?.core?.invokeOp;
      #|  window.__attributeProbe = [];
      #|  window.__MoonBit__.events.on("add.addFinished", (event) => {
      #|    window.__attributeProbe.push({
      #|      name: event.name,
      #|      extension: event.extension,
      #|      total: event.payload.total,
      #|    });
      #|  });
      #|  const reply = await window.__MoonBit__.add.slowAdd({
      #|    left: 20,
      #|    right: 22,
      #|    delay_ms: 25,
      #|  });
      #|  return {
      #|    url: location.href,
      #|    title: document.title,
      #|    has_bridge: typeof invoke === "function",
      #|    has_generated_proxy: typeof window.__MoonBit__?.add?.slowAdd === "function",
      #|    has_event_api: typeof window.__MoonBit__?.events?.on === "function",
      #|    reply,
      #|    events: window.__attributeProbe,
      #|  };
      #|})()
    ),
    true,
  )
  let result : AttributeScenarioProbe = decode_probe(value, "attribute codegen")
  guard result.url == "https://proton.localhost/" &&
    result.title == "Proton Attribute Codegen" else {
    fail("attribute codegen page identity mismatch: " + value.stringify())
  }
  guard result.has_bridge && result.has_generated_proxy && result.has_event_api else {
    fail("attribute codegen bridge was not installed: " + value.stringify())
  }
  guard result.reply.total == 42 && result.reply.waited_ms == 25 else {
    fail("attribute codegen reply mismatch: " + value.stringify())
  }
  guard result.events.length() == 1 else {
    fail("attribute codegen event count mismatch: " + value.stringify())
  }
  let event = result.events[0]
  guard event.name == "addFinished" &&
    event.extension == "add" &&
    event.total == 42 else {
    fail("attribute codegen event mismatch: " + value.stringify())
  }
}

///|
fn assert_extension_scenario_native_log(
  name : String,
  path : String,
) -> Unit raise {
  let required_ops : Array[String] = match name {
    "38_async_extension_add" | "42_attribute_codegen_commands" =>
      ["ext:add/slowAdd"]
    "39_sync_async_extensions" => ["ext:math/double", "ext:add/slowAdd"]
    _ => fail("unsupported extension log scenario: " + name)
  }
  for op in required_ops {
    guard count_native_log_entries(path, "bridge_enqueue", "op=" + op) > 0 else {
      fail("native log did not record " + op + " for " + name)
    }
  }
}
