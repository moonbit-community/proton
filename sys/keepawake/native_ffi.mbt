///|
/// Private handle for the synchronous macOS and Windows backends.
priv type NativeGuard

///|
/// Creates a native keep-awake guard.
#borrow(reason)
extern "C" fn native_guard_create(reason : Bytes, scope : Int32) -> NativeGuard = "moonbit_keepawake_guard_create"

///|
/// Returns whether a native guard is still active.
#borrow(handle)
extern "C" fn native_guard_is_active(handle : NativeGuard) -> Bool = "moonbit_keepawake_guard_is_active"

///|
/// Returns the latest backend status code recorded on the guard.
#borrow(handle)
extern "C" fn native_guard_status(handle : NativeGuard) -> Int32 = "moonbit_keepawake_guard_status"

///|
/// Returns the scope code associated with the guard.
#borrow(handle)
extern "C" fn native_guard_scope_code(handle : NativeGuard) -> Int32 = "moonbit_keepawake_guard_scope_code"

///|
/// Returns the latest backend error message.
#borrow(handle)
extern "C" fn native_guard_last_error(handle : NativeGuard) -> Bytes = "moonbit_keepawake_guard_last_error"

///|
/// Releases the native keep-awake request if it is still active.
#borrow(handle)
extern "C" fn native_guard_release(handle : NativeGuard) -> Int32 = "moonbit_keepawake_guard_release"

///|
/// Indicates a successful native backend operation.
let native_status_ok : Int32 = 0

///|
/// Indicates that the backend is unavailable in the current environment.
let native_status_backend_unavailable : Int32 = 1

///|
/// Indicates that the backend exists but the operation still failed.
let native_status_operation_failed : Int32 = 2
