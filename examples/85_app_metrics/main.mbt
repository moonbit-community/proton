///|
struct SampleRequest {
  action : String
} derive(ToJson, FromJson)

///|
pub extend SampleRequest with ToJson::{to_json}

///|
pub extend SampleRequest with FromJson::{from_json}

///|
struct MetricRow {
  task_id : Int64
  kind : String
  cpu_percent : Double
  memory_mb : Double
  name : String
} derive(ToJson, FromJson)

///|
pub extend MetricRow with ToJson::{to_json}

///|
pub extend MetricRow with FromJson::{from_json}

///|
struct SampleReply {
  ok : Bool
  message : String
  measured : Bool
  metrics : Array[MetricRow]
} derive(ToJson, FromJson)

///|
pub extend SampleReply with ToJson::{to_json}

///|
pub extend SampleReply with FromJson::{from_json}

///|
let contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/app-metrics",
  js_namespace="appMetrics",
)

///|
let sample_command : @proton_contract.Command[SampleRequest, SampleReply] = contract.command(
  "sample",
)

///|
/// The running application context, retained for command handlers.
let application_slot : Ref[@proton.ApplicationContext?] = { val: None, }

///|
/// Emits one review line for the terminal that started the example.
fn log_metrics_step(step : String) -> Unit {
  println("[app-metrics] " + step)
}

///|
/// Names one application process type for the review output.
fn metric_kind(process_type : @proton.AppProcessType) -> String {
  match process_type {
    @proton.AppProcessType::Unknown => "unknown"
    @proton.AppProcessType::Browser => "browser"
    @proton.AppProcessType::Gpu => "gpu"
    @proton.AppProcessType::Zygote => "zygote"
    @proton.AppProcessType::Utility => "utility"
    @proton.AppProcessType::Renderer => "renderer"
    @proton.AppProcessType::Extension => "extension"
    @proton.AppProcessType::Guest => "guest"
    @proton.AppProcessType::Plugin => "plugin"
    @proton.AppProcessType::SandboxHelper => "sandbox-helper"
    @proton.AppProcessType::Worker => "worker"
  }
}

///|
/// Renders the memory footprint in megabytes, or `-` while Chromium has not
/// measured the process.
fn metric_memory_mb(metric : @proton.AppProcessMetric) -> Double {
  if metric.memory_bytes < 0L {
    -1.0
  } else {
    metric.memory_bytes.to_double() / (1024.0 * 1024.0)
  }
}

///|
fn metric_rows(metrics : Array[@proton.AppProcessMetric]) -> Array[MetricRow] {
  let rows : Array[MetricRow] = []
  for metric in metrics {
    rows.push({
      task_id: metric.task_id,
      kind: metric_kind(metric.process_type),
      cpu_percent: metric.cpu_percent,
      memory_mb: metric_memory_mb(metric),
      name: metric.name,
    })
  }
  rows
}

///|
/// Reports whether Chromium has measured a memory footprint for any process.
fn sample_measured(rows : Array[MetricRow]) -> Bool {
  for row in rows {
    if row.memory_mb >= 0.0 {
      return true
    }
  }
  false
}

///|
fn describe_sample(rows : Array[MetricRow]) -> String {
  let parts : Array[String] = []
  for row in rows {
    parts.push(
      row.kind +
      "#" +
      row.task_id.to_string() +
      " cpu=" +
      row.cpu_percent.to_string() +
      " mem_mb=" +
      row.memory_mb.to_string(),
    )
  }
  parts.join(" | ")
}

///|
/// Reads one `app.getAppMetrics()` snapshot. The first call of a run starts
/// Chromium's sampling, so it reports no memory footprint and the CPU column
/// stays zero until one sampling interval has passed.
fn measure() -> SampleReply {
  let context = match application_slot.val {
    Some(context) => context
    None =>
      return {
        ok: false,
        message: "Application context is not ready",
        measured: false,
        metrics: [],
      }
  }
  let metrics = context.app_metrics() catch {
    error => {
      log_metrics_step("sample failed: " + error.message())
      return {
        ok: false,
        message: error.message(),
        measured: false,
        metrics: [],
      }
    }
  }
  let rows = metric_rows(metrics)
  let measured = sample_measured(rows)
  log_metrics_step(
    "sample: " +
    rows.length().to_string() +
    " processes, measured=" +
    measured.to_string() +
    " " +
    describe_sample(rows),
  )
  {
    ok: true,
    message: if measured {
      "Chromium reported " +
      rows.length().to_string() +
      " processes; CPU is the usage since the previous sample"
    } else {
      "Sampling started; sample again for memory and CPU values"
    },
    measured,
    metrics: rows,
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(sample_command, (_context, _request) => measure())
}

///|
fn page() -> String {
  (
    #|<!doctype html>
    #|<html lang="en">
    #|  <head>
    #|    <meta charset="utf-8">
    #|    <meta name="viewport" content="width=device-width, initial-scale=1">
    #|    <title>Application Metrics</title>
    #|    <style>
    #|      :root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; background: #101418; color: #eef3f6; }
    #|      * { box-sizing: border-box; }
    #|      body { margin: 0; min-height: 100vh; background: #101418; }
    #|      button { font: inherit; cursor: pointer; }
    #|      main { width: min(940px, calc(100vw - 40px)); margin: 0 auto; padding: 34px 0 46px; }
    #|      .eyebrow { margin: 0 0 10px; color: #58c7d8; font: 700 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; letter-spacing: .16em; text-transform: uppercase; }
    #|      h1 { margin: 0; font-size: clamp(26px, 4vw, 40px); letter-spacing: -.04em; }
    #|      .summary { margin: 12px 0 0; color: #9fb0bd; line-height: 1.55; }
    #|      code { padding: 1px 6px; border-radius: 4px; background: #1d242b; color: #cfe7ef; font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .toolbar { display: flex; align-items: center; gap: 12px; margin-top: 22px; }
    #|      .action { min-height: 42px; padding: 0 16px; border: 1px solid #2f6f63; border-radius: 8px; background: #20564d; color: #eef3f6; font-weight: 600; }
    #|      .toggle { display: flex; align-items: center; gap: 8px; color: #9fb0bd; font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .panel { margin-top: 18px; border: 1px solid #2b353d; border-radius: 12px; background: #151b21; overflow: hidden; }
    #|      .panel-head { display: flex; align-items: center; justify-content: space-between; min-height: 46px; padding: 0 16px; border-bottom: 1px solid #2b353d; color: #9fb0bd; font: 650 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; text-transform: uppercase; letter-spacing: .09em; }
    #|      table { width: 100%; border-collapse: collapse; font: 12px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      th, td { padding: 8px 16px; text-align: left; border-bottom: 1px solid #212a31; }
    #|      th { color: #8b9aa6; font-weight: 600; }
    #|      td.pending { color: #8b9aa6; }
    #|      .status { margin-top: 16px; padding: 14px 16px; border: 1px solid #2b353d; border-radius: 12px; background: #151b21; color: #cfe7ef; font: 12px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <header>
    #|        <p class="eyebrow">Electron app / review 85</p>
    #|        <h1>Application metrics</h1>
    #|        <p class="summary">
    #|          <code>ApplicationContext::app_metrics()</code> mirrors
    #|          <code>app.getAppMetrics()</code>. Chromium measures processes
    #|          only while something observes its task manager, so the first
    #|          sample of a run lists the processes without a memory footprint
    #|          and the CPU column fills in after one sampling interval (about
    #|          one second, two on macOS). Every sample prints one
    #|          <code>[app-metrics]</code> line in the terminal.
    #|        </p>
    #|      </header>
    #|      <div class="toolbar">
    #|        <button class="action" id="sample">Sample now</button>
    #|        <label class="toggle">
    #|          <input type="checkbox" id="auto"> sample every second
    #|        </label>
    #|      </div>
    #|      <section class="panel">
    #|        <div class="panel-head"><span>Processes</span><span id="count">-</span></div>
    #|        <table>
    #|          <thead>
    #|            <tr><th>type</th><th>task id</th><th>CPU</th><th>memory (MB)</th><th>name</th></tr>
    #|          </thead>
    #|          <tbody id="rows"></tbody>
    #|        </table>
    #|      </section>
    #|      <p class="status" id="status" role="status">Ready.</p>
    #|    </main>
    #|    <script>
    #|      const status = document.querySelector("#status");
    #|      const rows = document.querySelector("#rows");
    #|      async function invoke() {
    #|        return window.__MoonBit__.core.invokeOp("ext:appMetrics/sample", { action: "sample" });
    #|      }
    #|      function cell(text, pending) {
    #|        const td = document.createElement("td");
    #|        td.textContent = text;
    #|        if (pending) td.className = "pending";
    #|        return td;
    #|      }
    #|      function render(reply) {
    #|        rows.replaceChildren();
    #|        for (const metric of reply.metrics) {
    #|          const tr = document.createElement("tr");
    #|          const pending = metric.memory_mb < 0;
    #|          tr.append(
    #|            cell(metric.kind, false),
    #|            cell(String(metric.task_id), false),
    #|            cell(`${metric.cpu_percent.toFixed(2)}%`, false),
    #|            cell(pending ? "not measured" : metric.memory_mb.toFixed(1), pending),
    #|            cell(metric.name === "" ? "-" : metric.name, metric.name === ""),
    #|          );
    #|          rows.append(tr);
    #|        }
    #|        document.querySelector("#count").textContent = `${reply.metrics.length} processes`;
    #|        status.textContent = reply.ok ? reply.message : `Failed: ${reply.message}`;
    #|      }
    #|      async function sample() {
    #|        try {
    #|          render(await invoke());
    #|        } catch (error) {
    #|          status.textContent = `sample failed: ${String(error)}`;
    #|        }
    #|      }
    #|      let timer = null;
    #|      document.querySelector("#sample").addEventListener("click", () => void sample());
    #|      document.querySelector("#auto").addEventListener("change", (event) => {
    #|        if (timer !== null) {
    #|          clearInterval(timer);
    #|          timer = null;
    #|        }
    #|        if (event.target.checked) {
    #|          timer = setInterval(() => void sample(), 1000);
    #|        }
    #|      });
    #|      void sample();
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
async fn main {
  @proton.html("Application Metrics", page(), width=940, height=720)
  .identifier("com.example.proton.app-metrics")
  .commands(register_commands)
  .app_lifecycle(
    on_start=context => {
      application_slot.val = Some(context)
      // The first sample starts Chromium's task-manager sampling, so the
      // terminal shows both the empty first answer and the measured one.
      ignore(
        context
        .task_group()
        .spawn(
          () => {
            ignore(measure())
            @async.sleep(1000)
            ignore(measure())
            @async.sleep(2000)
            ignore(measure())
          },
          no_wait=true,
        ),
      )
      context
    },
    on_shutdown=fn(_context) { application_slot.val = None },
  )
  .run_or_abort()
}
