///|
fn CookieCompletionStore::CookieCompletionStore() -> CookieCompletionStore {
  { pending: [], }
}

///|
fn CookieCompletionStore::register(
  self : CookieCompletionStore,
  request_id : Int64,
) -> PendingCookieCompletion {
  let completion = PendingCookieCompletion::{
    request_id,
    state: CookieWaiting,
    changed: @async.CondVar::Cond(),
  }
  self.pending.push(completion)
  completion
}

///|
fn CookieCompletionStore::remove(
  self : CookieCompletionStore,
  request_id : Int64,
) -> Unit {
  for index, completion in self.pending {
    if completion.request_id == request_id {
      ignore(self.pending.remove(index))
      return
    }
  }
}

///|
fn CookieCompletionStore::route_completion(
  self : CookieCompletionStore,
  completion : @native.NativeCookieGetCompletion?,
) -> Bool {
  guard completion is Some(completion) else { return false }
  for pending in self.pending {
    if pending.request_id == completion.request_id {
      if pending.state is CookieWaiting {
        pending.state = CookieCompleted(completion.result)
        pending.changed.broadcast()
      }
      return true
    }
  }
  true
}

///|
async fn CookieCompletionStore::wait(
  self : CookieCompletionStore,
  request_id : Int64,
) -> Array[@native.NativeCookieRecord] raise WindowSessionError {
  let completion = self.register(request_id)
  defer self.remove(request_id)
  while completion.state is CookieWaiting {
    completion.changed.wait() catch {
      _ => raise Cancelled
    }
  }
  match completion.state {
    CookieCompleted(Ok(payload)) => payload
    CookieCompleted(Err(error)) =>
      raise window_operation_failed("complete cookie read", error)
    CookieWaiting => abort("cookie completion resumed without a result")
  }
}

///|
fn CookieSameSite::to_native(self : CookieSameSite) -> @native.CookieSameSite {
  match self {
    Unspecified => @native.CookieSameSite::Unspecified
    NoRestriction => @native.CookieSameSite::NoRestriction
    Lax => @native.CookieSameSite::Lax
    Strict => @native.CookieSameSite::Strict
  }
}

///|
fn cookie_same_site_from_native(
  value : @native.CookieSameSite,
) -> CookieSameSite {
  match value {
    @native.CookieSameSite::Unspecified => Unspecified
    @native.CookieSameSite::NoRestriction => NoRestriction
    @native.CookieSameSite::Lax => Lax
    @native.CookieSameSite::Strict => Strict
  }
}

///|
fn cookie_expiration_date(record : @native.NativeCookieRecord) -> Double? {
  match record.expires {
    Some(expires) =>
      // CEF stores base time as microseconds since the Windows epoch.
      Some((expires.to_double() - 11644473600000000.0) / 1000000.0)
    None => None
  }
}

///|
fn cookies_from_native(
  records : Array[@native.NativeCookieRecord],
) -> Array[Cookie] {
  records.map(record => {
    name: record.name,
    value: record.value,
    domain: record.domain,
    path: record.path,
    secure: record.secure,
    http_only: record.http_only,
    same_site: cookie_same_site_from_native(record.same_site),
    expiration_date: cookie_expiration_date(record),
  })
}

///|
/// Returns the window id whose request context owns this session.
pub fn SessionHandle::window_id(self : SessionHandle) -> String {
  self.id
}

///|
/// Returns cookies visible to the session, optionally restricted to one URL.
/// HTTP-only cookies are excluded unless `include_http_only` is `true`.
pub async fn SessionHandle::get_cookies(
  self : SessionHandle,
  url? : String,
  include_http_only? : Bool = false,
) -> Array[Cookie] raise WindowSessionError {
  (self.read_cookies)(url, include_http_only)
}

///|
/// Sets a cookie in the session's cookie store.
pub fn SessionHandle::set_cookie(
  self : SessionHandle,
  url : String,
  name : String,
  value : String,
  domain? : String,
  path? : String,
  secure? : Bool = false,
  http_only? : Bool = false,
  same_site? : CookieSameSite = Unspecified,
) -> Unit raise WindowSessionError {
  (self.write_cookie)(
    url, name, value, domain, path, secure, http_only, same_site,
  )
}

///|
/// Deletes matching cookies. Omitting both filters deletes all cookies.
pub fn SessionHandle::delete_cookies(
  self : SessionHandle,
  url? : String,
  name? : String,
) -> Unit raise WindowSessionError {
  (self.remove_cookies)(url, name)
}

///|
/// Flushes pending cookie changes to disk.
pub fn SessionHandle::flush_cookies(
  self : SessionHandle,
) -> Unit raise WindowSessionError {
  (self.flush_cookie_store)()
}

///|
/// Clears the session's HTTP cache.
pub fn SessionHandle::clear_cache(
  self : SessionHandle,
) -> Unit raise WindowSessionError {
  (self.clear_http_cache)()
}
