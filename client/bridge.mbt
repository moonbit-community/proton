///|
extern "js" fn bridge_available() -> Bool =
  #| () => Boolean(
  #|   globalThis.__MoonBit__ &&
  #|   globalThis.__MoonBit__.core &&
  #|   typeof globalThis.__MoonBit__.core.invokeJson === "function" &&
  #|   globalThis.__MoonBit__.events &&
  #|   typeof globalThis.__MoonBit__.events.onJson === "function"
  #| )

///|
extern "js" fn invoke_json(
  route : String,
  request_json : String,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[String] =
  #| (route, requestJson, signal) => {
  #|   const root = globalThis.__MoonBit__;
  #|   if (!root || !root.core ||
  #|       typeof root.core.invokeJson !== "function") {
  #|     return Promise.reject(JSON.stringify({
  #|       code: "bridge_unavailable",
  #|       message: "the Proton bridge is not available on this page",
  #|     }));
  #|   }
  #|   return root.core.invokeJson(route, requestJson, { signal }).catch((error) => {
  #|     const detail = error && error.detail;
  #|     return Promise.reject(JSON.stringify({
  #|       code: error && error.code ? String(error.code) : "transport_failure",
  #|       message: error && error.message
  #|         ? String(error.message)
  #|         : String(error || "Proton bridge request failed"),
  #|       ...(detail === undefined ? {} : { detail: String(detail) }),
  #|     }));
  #|   });
  #| }

///|
extern "js" fn invoke_json_with_callbacks(
  route : String,
  request_json : String,
  signal : @js_async.AbortSignal,
  success : (String) -> Unit,
  failure : (String) -> Unit,
) -> Unit =
  #| (route, requestJson, signal, success, failure) => {
  #|   const root = globalThis.__MoonBit__;
  #|   if (!root || !root.core ||
  #|       typeof root.core.invokeJson !== "function") {
  #|     failure(JSON.stringify({
  #|       code: "bridge_unavailable",
  #|       message: "the Proton bridge is not available on this page",
  #|     }));
  #|     return;
  #|   }
  #|   root.core.invokeJson(route, requestJson, { signal }).then(success, (error) => {
  #|     const detail = error && error.detail;
  #|     failure(JSON.stringify({
  #|       code: error && error.code ? String(error.code) : "transport_failure",
  #|       message: error && error.message
  #|         ? String(error.message)
  #|         : String(error || "Proton bridge request failed"),
  #|       ...(detail === undefined ? {} : { detail: String(detail) }),
  #|     }));
  #|   });
  #| }

///|
extern "js" fn subscribe_json(
  route : String,
  listener : (String) -> Unit,
) -> () -> Unit =
  #| (route, listener) => {
  #|   const root = globalThis.__MoonBit__;
  #|   return root.events.onJson(route, listener);
  #| }
