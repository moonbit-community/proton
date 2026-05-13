///|
/// Opaque CEF runtime handle owned by the native shim.
#external
type CefRuntimeHandle

///|
/// Opaque CEF browser view handle owned by the native shim.
#external
type CefViewHandle

///|
/// Opaque C string pointer received from CEF callbacks.
#external
priv type CefCStr

///|
/// Opaque binding handle returned by the native shim.
#external
type CefBindingHandle

///|
extern "C" fn cef_is_available() -> Bool = "lepus_cef_is_available"

///|
#borrow(cache_path, user_data_path, subprocess_path, locale)
extern "C" fn cef_runtime_initialize(
  cache_path : Bytes,
  user_data_path : Bytes,
  subprocess_path : Bytes,
  remote_debugging_port : Int,
  locale : Bytes,
  sandbox : Bool,
  debug : Bool,
) -> CefRuntimeHandle = "lepus_cef_runtime_initialize"

///|
extern "C" fn cef_runtime_status(runtime : CefRuntimeHandle) -> Int = "lepus_cef_runtime_status"

///|
extern "C" fn cef_runtime_destroy(runtime : CefRuntimeHandle) -> Int = "lepus_cef_runtime_destroy"

///|
extern "C" fn cef_runtime_run(runtime : CefRuntimeHandle) -> Int = "lepus_cef_runtime_run"

///|
extern "C" fn cef_runtime_quit(runtime : CefRuntimeHandle) -> Int = "lepus_cef_runtime_quit"

///|
#borrow(title)
extern "C" fn cef_view_create(
  runtime : CefRuntimeHandle,
  title : Bytes,
  width : Int,
  height : Int,
) -> CefViewHandle = "lepus_cef_view_create"

///|
extern "C" fn cef_view_status(view : CefViewHandle) -> Int = "lepus_cef_view_status"

///|
extern "C" fn cef_view_destroy(view : CefViewHandle) -> Int = "lepus_cef_view_destroy"

///|
extern "C" fn cef_view_identity(view : CefViewHandle) -> Int64 = "lepus_cef_view_identity"

///|
extern "C" fn cef_view_native_handle(view : CefViewHandle, kind : Int) -> Int64 = "lepus_cef_view_native_handle"

///|
#borrow(title)
extern "C" fn cef_view_set_title(view : CefViewHandle, title : Bytes) -> Int = "lepus_cef_view_set_title"

///|
extern "C" fn cef_view_set_size(
  view : CefViewHandle,
  width : Int,
  height : Int,
) -> Int = "lepus_cef_view_set_size"

///|
#borrow(html)
extern "C" fn cef_view_set_html(view : CefViewHandle, html : Bytes) -> Int = "lepus_cef_view_set_html"

///|
#borrow(url)
extern "C" fn cef_view_navigate(view : CefViewHandle, url : Bytes) -> Int = "lepus_cef_view_navigate"

///|
#borrow(script)
extern "C" fn cef_view_init(view : CefViewHandle, script : Bytes) -> Int = "lepus_cef_view_init"

///|
#borrow(script)
extern "C" fn cef_view_eval(view : CefViewHandle, script : Bytes) -> Int = "lepus_cef_view_eval"

///|
extern "C" fn cef_view_dispatch(
  view : CefViewHandle,
  call_closure : FuncRef[(CefViewHandle, (CefViewHandle) -> Unit) -> Unit],
  closure : () -> Unit,
) -> Int = "lepus_cef_view_dispatch"

///|
#borrow(name)
#owned(closure)
extern "C" fn cef_view_bind(
  view : CefViewHandle,
  name : Bytes,
  call_closure : FuncRef[(CefCStr, CefCStr, (Bytes, Bytes) -> Unit) -> Unit],
  closure : (Bytes, Bytes) -> Unit,
) -> CefBindingHandle = "lepus_cef_view_bind"

///|
#borrow(name)
extern "C" fn cef_view_unbind(
  view : CefViewHandle,
  name : Bytes,
  binding : CefBindingHandle,
) -> Int = "lepus_cef_view_unbind"

///|
#borrow(seq, result)
extern "C" fn cef_view_response(
  view : CefViewHandle,
  seq : Bytes,
  status : Int,
  result : Bytes,
) -> Int = "lepus_cef_view_response"

///|
extern "C" fn cef_copy_cstr(cstr : CefCStr) -> Bytes = "lepus_cef_copy_cstr"

///|
extern "C" fn cef_binding_is_null(binding : CefBindingHandle) -> Bool = "lepus_cef_is_null"
