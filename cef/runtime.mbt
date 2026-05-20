///|
let cef_status_ok = 0

///|
let cef_status_unsupported = 1

///|
let cef_status_invalid_argument = 2

///|
let cef_status_invalid_state = 3

///|
let cef_status_native_error = 4

///|
/// Native handle kinds exposed by CEF views.
pub(all) enum CefNativeHandleKind {
  Window = 0
  Browser = 1
} derive(Debug, Eq)

///|
/// Initialized CEF runtime.
///
/// A process should own one runtime and create browser views from it. The MVP
/// keeps the CEF lifetime explicit so future subprocess/bootstrap support has a
/// natural place to attach.
pub struct CefRuntime {
  handle : CefRuntimeHandle
  mut destroyed : Bool
}

///|
/// One CEF browser view.
pub struct CefView {
  handle : CefViewHandle
  bindings : Map[String, CefBindingHandle]
  destroy_hooks : Map[String, () -> Unit]
  mut destroyed : Bool
}

///|
fn status_error(operation : String, status : Int) -> String {
  if status == cef_status_unsupported {
    operation + " failed: CEF backend is not linked in this binary"
  } else if status == cef_status_invalid_argument {
    operation + " failed: invalid native argument"
  } else if status == cef_status_invalid_state {
    operation + " failed: invalid CEF runtime state"
  } else if status == cef_status_native_error {
    operation + " failed: native CEF error"
  } else {
    operation + " failed: unknown CEF status \{status}"
  }
}

///|
fn unit_from_status(operation : String, status : Int) -> Result[Unit, String] {
  if status == cef_status_ok {
    Ok(())
  } else {
    Err(status_error(operation, status))
  }
}

///|
/// Initializes the CEF runtime.
///
/// The default native shim returns `Err` until the real CEF SDK shim is linked.
pub fn CefRuntime::initialize(
  settings? : CefSettings = CefSettings::new(),
) -> Result[CefRuntime, String] {
  let handle = cef_runtime_initialize(
    optional_cstr(settings.cache_path),
    optional_cstr(settings.user_data_path),
    optional_cstr(settings.subprocess_path),
    optional_port(settings.remote_debugging_port),
    optional_cstr(settings.locale),
    settings.sandbox,
    settings.debug,
  )
  let status = cef_runtime_status(handle)
  if status == cef_status_ok {
    Ok(CefRuntime::{ handle, destroyed: false })
  } else {
    ignore(cef_runtime_destroy(handle))
    Err(status_error("CefRuntime::initialize", status))
  }
}

///|
/// Shuts down the CEF runtime.
pub fn CefRuntime::destroy(self : CefRuntime) -> Result[Unit, String] {
  if self.destroyed {
    return Ok(())
  }
  self.destroyed = true
  unit_from_status("CefRuntime::destroy", cef_runtime_destroy(self.handle))
}

///|
/// Runs the CEF message loop.
pub fn CefRuntime::run(self : CefRuntime) -> Result[Unit, String] {
  unit_from_status("CefRuntime::run", cef_runtime_run(self.handle))
}

///|
/// Requests the CEF message loop to quit.
pub fn CefRuntime::quit(self : CefRuntime) -> Result[Unit, String] {
  unit_from_status("CefRuntime::quit", cef_runtime_quit(self.handle))
}

///|
/// Creates one CEF browser view.
pub fn CefRuntime::create_view(
  self : CefRuntime,
  options? : CefWindowOptions = CefWindowOptions::new(),
) -> Result[CefView, String] {
  let handle = cef_view_create(
    self.handle,
    @ffi.to_cstr(options.title),
    options.width,
    options.height,
  )
  let status = cef_view_status(handle)
  if status == cef_status_ok {
    Ok(CefView::{ handle, bindings: {}, destroy_hooks: {}, destroyed: false })
  } else {
    ignore(cef_view_destroy(handle))
    Err(status_error("CefRuntime::create_view", status))
  }
}

///|
/// Destroys this browser view and releases binding callbacks.
pub fn CefView::destroy(self : CefView) -> Result[Unit, String] {
  if self.destroyed {
    return Ok(())
  }
  self.destroyed = true
  let hooks : Array[() -> Unit] = []
  for _, hook in self.destroy_hooks {
    hooks.push(hook)
  }
  self.destroy_hooks.clear()
  for hook in hooks {
    hook()
  }
  for name, binding in self.bindings {
    ignore(cef_view_unbind(self.handle, @ffi.to_cstr(name), binding))
  }
  self.bindings.clear()
  unit_from_status("CefView::destroy", cef_view_destroy(self.handle))
}

///|
/// Returns a stable identity token for this native CEF view.
pub fn CefView::runtime_handle_id(self : CefView) -> Int64 {
  cef_view_identity(self.handle)
}

///|
/// Returns a native window or browser handle when the backend can provide one.
pub fn CefView::get_native_handle(
  self : CefView,
  kind : CefNativeHandleKind,
) -> Int64 {
  match kind {
    Window => cef_view_native_handle(self.handle, 0)
    Browser => cef_view_native_handle(self.handle, 1)
  }
}

///|
/// Schedules work on the CEF UI boundary.
pub fn CefView::dispatch(
  self : CefView,
  callback : () -> Unit,
) -> Result[Unit, String] {
  unit_from_status(
    "CefView::dispatch",
    cef_view_dispatch(self.handle, fn(_view, f) { f(_view) }, callback),
  )
}

///|
/// Updates the native window title.
pub fn CefView::set_title(
  self : CefView,
  title : String,
) -> Result[Unit, String] {
  unit_from_status(
    "CefView::set_title",
    cef_view_set_title(self.handle, @ffi.to_cstr(title)),
  )
}

///|
/// Updates the native window size.
pub fn CefView::set_size(
  self : CefView,
  width : Int,
  height : Int,
) -> Result[Unit, String] {
  unit_from_status(
    "CefView::set_size",
    cef_view_set_size(self.handle, width, height),
  )
}

///|
/// Loads HTML into the main frame.
pub fn CefView::set_html(self : CefView, html : String) -> Result[Unit, String] {
  unit_from_status(
    "CefView::set_html",
    cef_view_set_html(self.handle, @ffi.to_cstr(html)),
  )
}

///|
/// Navigates the main frame to a URL.
pub fn CefView::navigate(self : CefView, url : String) -> Result[Unit, String] {
  unit_from_status(
    "CefView::navigate",
    cef_view_navigate(self.handle, @ffi.to_cstr(url)),
  )
}

///|
/// Registers JavaScript that should run before future document scripts.
pub fn CefView::init(self : CefView, script : String) -> Result[Unit, String] {
  unit_from_status(
    "CefView::init",
    cef_view_init(self.handle, @ffi.to_cstr(script)),
  )
}

///|
/// Evaluates JavaScript in the current main frame.
pub fn CefView::eval(self : CefView, script : String) -> Result[Unit, String] {
  unit_from_status(
    "CefView::eval",
    cef_view_eval(self.handle, @ffi.to_cstr(script)),
  )
}

///|
/// Binds a JavaScript-to-native callback name.
pub fn CefView::bind(
  self : CefView,
  name : String,
  callback : (Bytes, Bytes) -> Unit,
) -> Result[Unit, String] {
  let binding = cef_view_bind(
    self.handle,
    @ffi.to_cstr(name),
    fn(raw_id, raw_req, callback) {
      let id = cef_copy_cstr(raw_id)
      let req = cef_copy_cstr(raw_req)
      callback(id, req)
    },
    callback,
  )
  if cef_binding_is_null(binding) {
    Err("CefView::bind failed: native binding was not created")
  } else {
    self.bindings.set(name, binding)
    Ok(())
  }
}

///|
/// Removes a JavaScript-to-native callback binding.
pub fn CefView::unbind(self : CefView, name : String) -> Result[Unit, String] {
  match self.bindings.get(name) {
    Some(binding) => {
      self.bindings.remove(name)
      unit_from_status(
        "CefView::unbind",
        cef_view_unbind(self.handle, @ffi.to_cstr(name), binding),
      )
    }
    None => Ok(())
  }
}

///|
/// Responds to a JavaScript binding call.
pub fn CefView::response(
  self : CefView,
  id : String,
  status : Int,
  result : String,
) -> Result[Unit, String] {
  unit_from_status(
    "CefView::response",
    cef_view_response(
      self.handle,
      @ffi.to_cstr(id),
      status,
      @ffi.to_cstr(result),
    ),
  )
}

///|
/// Registers a named callback that runs before the view is destroyed.
pub fn CefView::register_destroy_hook(
  self : CefView,
  hook_name : String,
  hook : () -> Unit,
) -> Unit {
  guard self.destroy_hooks.get(hook_name) is None else {
    abort(
      "CefView::register_destroy_hook: hook already registered: " + hook_name,
    )
  }
  self.destroy_hooks.set(hook_name, hook)
}

///|
/// Removes a destroy hook by name.
pub fn CefView::unregister_destroy_hook(
  self : CefView,
  hook_name : String,
) -> Unit {
  self.destroy_hooks.remove(hook_name)
}
