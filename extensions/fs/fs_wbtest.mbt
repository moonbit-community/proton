///|
test "fs spec rejects unsupported options" {
  match
    spec().build_extension(
      @core.ExtensionBuildContext::new(
        options=Some(Json::object({ "deprecated": Json::boolean(true) })),
      ),
    ) {
    Ok(_) => abort("expected fs extension options rejection")
    Err(error) => assert_eq(error, "fs extension options are not supported")
  }
}

///|
test "fs helper script stays with fs extension assets" {
  let script = fs_helper_script()
  assert_true(script.contains("const rootName = \"__MoonBit__\";"))
  assert_true(script.contains("const extensionName = \"fs\";"))
  assert_true(script.contains("@@nodeStyleFs"))
  assert_true(script.contains("api.sharedBufferSupport = function()"))
  assert_true(script.contains("api.readFileBuffer = function(path)"))
  assert_true(
    script.contains("api.writeFileBuffer = function(path, content, options)"),
  )
}

///|
test "fs shared buffer helpers validate transfer sizes" {
  assert_eq(shared_buffer_capacity(0), 1)
  assert_eq(shared_buffer_capacity(8), 8)
  debug_inspect(validate_shared_buffer_size(0), content="Ok(())")
  debug_inspect(
    validate_shared_buffer_size(-1),
    content="Err(\"fs SharedArrayBuffer size must be non-negative\")",
  )
  debug_inspect(
    validate_shared_buffer_size(shared_buffer_max_transfer_size + 1),
    content="Err(\"fs SharedArrayBuffer size exceeds the 64 MiB transfer limit: 67108865\")",
  )
}

///|
fn write_text_fixture(path : String, content : String) -> Unit {
  try @xfs.write_string_to_file(path, content) catch {
    error =>
      abort(
        "Failed to write fixture file: " + @debug.render(@debug.to_repr(error)),
      )
  } noraise {
    _ => ()
  }
}

///|
struct FsRuntimeReport {
  content : String
  bytes_read : Int
} derive(FromJson, Eq, Debug)

///|
fn[Payload : @json.FromJson] decode_single_argument(
  raw_req : Bytes,
) -> Result[Payload, String] {
  try {
    let request_json : Json = @json.parse(@ffi.from_cstr(raw_req))
    let request_args : Array[Payload] = @json.from_json(request_json)
    if request_args.length() == 1 {
      Ok(request_args[0])
    } else {
      Err("Expected exactly one argument")
    }
  } catch {
    err => Err(err.to_string())
  }
}

///|
test "fs path api can read write and append text files" {
  let path = "lepus-fs-path-api.txt"
  match write_text_file(path, "hello", None) {
    Ok(reply) => {
      assert_true(reply.written)
      assert_eq(reply.bytes_written, 5)
    }
    Err(error) => abort(error)
  }
  match append_text_file(path, " world", None) {
    Ok(reply) => {
      assert_true(reply.written)
      assert_eq(reply.bytes_written, 6)
    }
    Err(error) => abort(error)
  }
  match read_text_file(path, None) {
    Ok(reply) => {
      assert_eq(reply.content, "hello world")
      assert_eq(reply.bytes_read, 11)
    }
    Err(error) => abort(error)
  }
  @debug.assert_eq(native_remove_file(path), Ok(true))
}

///|
test "fs extension text ops complete through WebView promise bridge" {
  let path = "lepus-fs-webview-promise.txt"
  if native_path_exists(path) {
    ignore(native_remove_file(path))
  }
  let expected_report = FsRuntimeReport::{
    content: "hello world",
    bytes_read: 11,
  }
  let mut seen_report : FsRuntimeReport? = None
  let mut js_error : String? = None
  let webview = @webview.Webview::new()
  @core.install_extension(webview, extension())
  webview.bind("reportFsFailure", fn(id, req) {
    let request_id = @ffi.from_cstr(id)
    let message_result : Result[String, String] = decode_single_argument(req)
    match message_result {
      Ok(message) => js_error = Some(message)
      Err(message) =>
        js_error = Some("Failed to decode fs failure payload: " + message)
    }
    webview.response(request_id, 0, "null")
    webview.terminate()
  })
  webview.bind("reportFsRuntime", fn(id, req) {
    let request_id = @ffi.from_cstr(id)
    let report_result : Result[FsRuntimeReport, String] = decode_single_argument(
      req,
    )
    match report_result {
      Ok(report) => seen_report = Some(report)
      Err(message) =>
        js_error = Some("Failed to decode fs runtime report: " + message)
    }
    webview.response(request_id, 0, "null")
    webview.terminate()
  })
  webview.set_html(
    (
      #| <html>
      #|   <body>
      #|     <script>
      #|       const path = "lepus-fs-webview-promise.txt";
      #|       const reportFailure = (message) =>
      #|         window.reportFsFailure(message).catch(() => {});
      #|       const waitFor = (predicate, onReady, label, attempts = 0) => {
      #|         if (predicate()) {
      #|           onReady();
      #|           return;
      #|         }
      #|         if (attempts >= 50) {
      #|           void reportFailure(label + " timeout");
      #|           return;
      #|         }
      #|         window.setTimeout(() => {
      #|           waitFor(predicate, onReady, label, attempts + 1);
      #|         }, 20);
      #|       };
      #|       window.addEventListener("error", (event) => {
      #|         void reportFailure("window error: " + String(event.message));
      #|       });
      #|       window.addEventListener("unhandledrejection", (event) => {
      #|         void reportFailure("unhandled rejection: " + String(event.reason));
      #|       });
      #|       window.addEventListener("load", () => {
      #|         waitFor(
      #|           () => {
      #|             const moonbit = window.__MoonBit__;
      #|             return !!moonbit && !!moonbit.fs;
      #|           },
      #|           () => {
      #|             const timeoutId = window.setTimeout(() => {
      #|               void reportFailure("fs promise report timeout");
      #|             }, 1000);
      #|             const fs = window.__MoonBit__.fs;
      #|             fs.writeFile(path, "hello")
      #|               .then(() => fs.appendFile(path, " world"))
      #|               .then(() => fs.readFile(path))
      #|               .then((reply) => {
      #|                 window.clearTimeout(timeoutId);
      #|                 return window.reportFsRuntime({
      #|                   content: reply.content,
      #|                   bytes_read: reply.bytes_read,
      #|                 });
      #|               })
      #|               .catch((error) => {
      #|                 window.clearTimeout(timeoutId);
      #|                 void reportFailure("fs promise transport error: " + String(error));
      #|               });
      #|           },
      #|           "__MoonBit__.fs",
      #|         );
      #|       });
      #|     </script>
      #|   </body>
      #| </html>,
    ),
  )
  webview.run()
  if native_path_exists(path) {
    ignore(native_remove_file(path))
  }
  assert_true(js_error is None)
  assert_true(seen_report == Some(expected_report))
}

///|
test "fs path api can stat rename and copy files" {
  let path = "lepus-fs-stat-source.txt"
  let renamed = "lepus-fs-stat-renamed.txt"
  let copied = "lepus-fs-stat-copy.txt"
  write_text_fixture(path, "abc123")

  match stat_path(path, true) {
    Ok(stat) => {
      assert_true(stat.exists)
      assert_true(stat.is_file)
      assert_false(stat.is_dir)
      assert_eq(stat.size, 6)
    }
    Err(error) => abort(error)
  }

  match copy_file_path(path, copied, true) {
    Ok(bytes_copied) => assert_eq(bytes_copied, 6)
    Err(error) => abort(error)
  }
  match rename_path(path, renamed) {
    Ok(_) => ()
    Err(error) => abort(error)
  }
  assert_false(native_path_exists(path))
  assert_true(native_path_exists(renamed))
  assert_true(native_path_exists(copied))
  @debug.assert_eq(native_remove_file(renamed), Ok(true))
  @debug.assert_eq(native_remove_file(copied), Ok(true))
}

///|
test "fs path api can create directories recursively" {
  let root = "lepus-fs-dir-api"
  let child = join_native_child_path(root, "nested")

  if native_path_exists(root) {
    ignore(remove_path(root, true, true))
  }

  match mkdir_path(child, true) {
    Ok(created) => assert_true(created)
    Err(error) => abort(error)
  }

  assert_true(native_path_exists(root))
  assert_true(is_path_dir(root))
  assert_true(native_path_exists(child))
  assert_true(is_path_dir(child))

  @debug.assert_eq(native_remove_dir(child), Ok(true))
  @debug.assert_eq(native_remove_dir(root), Ok(true))
}

///|
test "fs path api can list directories recursively" {
  let root = "lepus-fs-list-api"
  let child = join_native_child_path(root, "nested")
  let file = join_native_child_path(child, "demo.txt")

  if native_path_exists(root) {
    ignore(remove_path(root, true, true))
  }

  match mkdir_path(child, true) {
    Ok(_) => ()
    Err(error) => abort(error)
  }
  write_text_fixture(file, "demo")

  match readdir_entries(root, true) {
    Ok(entries) => {
      assert_true(entries.contains("nested"))
      assert_true(entries.contains("nested/demo.txt"))
    }
    Err(error) => abort(error)
  }

  @debug.assert_eq(native_remove_file(file), Ok(true))
  @debug.assert_eq(native_remove_dir(child), Ok(true))
  @debug.assert_eq(native_remove_dir(root), Ok(true))
}

///|
test "fs path api can remove directories recursively" {
  let root = "lepus-fs-remove-api"
  let child = join_native_child_path(root, "nested")
  let file = join_native_child_path(child, "demo.txt")

  if native_path_exists(root) {
    ignore(remove_path(root, true, true))
  }

  match mkdir_path(child, true) {
    Ok(_) => ()
    Err(error) => abort(error)
  }
  write_text_fixture(file, "demo")

  match remove_path(root, true, false) {
    Ok(removed) => assert_true(removed)
    Err(error) => abort(error)
  }
  match stat_path(root, false) {
    Ok(stat) => assert_false(stat.exists)
    Err(error) => abort(error)
  }
}

///|
test "fs path api can truncate files and measure size" {
  let path = "lepus-fs-truncate.txt"
  write_text_fixture(path, "abcdef")

  match truncate_path(path, 3) {
    Ok(size) => assert_eq(size, 3)
    Err(error) => abort(error)
  }
  match read_text_file(path, None) {
    Ok(reply) => assert_eq(reply.content, "abc")
    Err(error) => abort(error)
  }
  match recursive_path_size(path) {
    Ok(size) => assert_eq(size, 3)
    Err(error) => abort(error)
  }
  @debug.assert_eq(native_remove_file(path), Ok(true))
}
