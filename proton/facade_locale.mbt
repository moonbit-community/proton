///|
/// Failures produced while querying the operating system's language order.
pub(all) suberror SystemLocaleError {
  NativeQuery(status~ : Int, detail~ : String)
} derive(Debug)

///|
pub extend SystemLocaleError with Debug::{to_repr}

///|
pub fn SystemLocaleError::message(self : SystemLocaleError) -> String {
  match self {
    NativeQuery(status~, detail~) =>
      "failed to query system preferred languages (" +
      status.to_string() +
      "): " +
      detail
  }
}

///|
impl Show for SystemLocaleError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub extend SystemLocaleError with Show::{to_string, output}

///|
/// Returns the operating system's valid preferred languages in preference
/// order. Invalid platform entries are ignored.
pub fn system_preferred_languages() -> Array[@locale.Locale] raise SystemLocaleError {
  let raw = @native.system_preferred_language_tags() catch {
    error => raise NativeQuery(status=error.status(), detail=error.message())
  }
  let platform = @native.runtime_info().platform catch {
      error => raise NativeQuery(status=error.status(), detail=error.message())
    }
  normalize_platform_languages(raw, posix=platform == "linux")
}

///|
fn normalize_platform_languages(
  values : Array[String],
  posix~ : Bool,
) -> Array[@locale.Locale] {
  if !posix {
    return @locale.normalize_system_languages(values)
  }
  let tags : Array[String] = []
  for value in values {
    for candidate in @locale.posix_locale_candidates(value) {
      tags.push(candidate)
    }
  }
  @locale.normalize_system_languages(tags)
}

///|
fn resolve_locale_preferences(
  explicit : @locale.Locale?,
) -> @locale.LocalePreferences {
  let system = system_preferred_languages() catch {
    _ => {
      @xlog.warn(category="proton.locale") <?
        { "message": "system locale query failed; falling back to en-US" }
      []
    }
  }
  @locale.LocalePreferences::resolve(explicit, system)
}
