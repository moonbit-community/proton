///|
/// Represents a native keep-awake request managed by the current platform.
///
/// A `Guard` is created by `acquire` and released explicitly through
/// `Guard::release` or implicitly when the runtime reclaims it. The type is
/// intentionally opaque so callers interact only through the safe public API
/// instead of depending on backend-specific state layout.
pub type Guard

///|
/// Creates a native keep-awake guard.
#borrow(reason)
extern "C" fn native_guard_create(reason : Bytes, scope : Int) -> Guard = "moonbit_keepawake_guard_create"

///|
/// Returns whether a native guard is still active.
#borrow(handle)
extern "C" fn native_guard_is_active(handle : Guard) -> Bool = "moonbit_keepawake_guard_is_active"

///|
/// Returns the latest backend status code recorded on the guard.
#borrow(handle)
extern "C" fn native_guard_status(handle : Guard) -> Int = "moonbit_keepawake_guard_status"

///|
/// Returns the scope code associated with the guard.
#borrow(handle)
extern "C" fn native_guard_scope_code(handle : Guard) -> Int = "moonbit_keepawake_guard_scope_code"

///|
/// Returns the latest backend error message.
#borrow(handle)
extern "C" fn native_guard_last_error(handle : Guard) -> Bytes = "moonbit_keepawake_guard_last_error"

///|
/// Releases the native keep-awake request if it is still active.
#borrow(handle)
extern "C" fn native_guard_release(handle : Guard) -> Int = "moonbit_keepawake_guard_release"

///|
/// Indicates a successful native backend operation.
let native_status_ok : Int = 0

///|
/// Indicates that the backend is unavailable in the current environment.
let native_status_backend_unavailable : Int = 1

///|
/// Indicates that the backend exists but the operation still failed.
let native_status_operation_failed : Int = 2
