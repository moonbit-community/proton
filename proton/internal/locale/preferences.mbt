///|
/// The immutable locale selection for one Proton application session.
pub struct LocalePreferences {
  locale_value : Locale
  preferred_values : Array[Locale]
} derive(Debug, Eq)

///|
pub extend LocalePreferences with Eq::{not_equal, equal}

///|
pub extend LocalePreferences with Debug::{to_repr}

///|
#doc(hidden)
pub fn LocalePreferences::resolve(
  explicit : Locale?,
  system : Array[Locale],
) -> LocalePreferences {
  let preferred : Array[Locale] = []
  match explicit {
    Some(locale) => push_unique_locale(preferred, locale)
    None => ()
  }
  for locale in system {
    push_unique_locale(preferred, locale)
  }
  let english = Locale::parse("en-US") catch {
    _ => abort("invalid fallback locale")
  }
  push_unique_locale(preferred, english)
  { locale_value: preferred[0], preferred_values: preferred }
}

///|
/// Returns the immutable primary application locale.
pub fn LocalePreferences::locale(self : LocalePreferences) -> Locale {
  self.locale_value
}

///|
/// Returns a copy of the ordered, deduplicated language preferences.
pub fn LocalePreferences::preferred_languages(
  self : LocalePreferences,
) -> Array[Locale] {
  self.preferred_values.copy()
}

///|
#doc(hidden)
pub fn LocalePreferences::chromium_locale(self : LocalePreferences) -> Locale {
  for locale in self.preferred_values {
    match locale.matching_tag() {
      Some(tag) =>
        return Locale::parse(tag) catch {
          _ => abort("invalid normalized Chromium locale")
        }
      None => ()
    }
  }
  Locale::parse("en-US") catch {
    _ => abort("invalid fallback locale")
  }
}

///|
#doc(hidden)
pub fn LocalePreferences::accept_languages(
  self : LocalePreferences,
) -> Array[Locale] {
  self.preferred_values.copy()
}

///|
#doc(hidden)
pub fn normalize_system_languages(values : Array[String]) -> Array[Locale] {
  let locales : Array[Locale] = []
  for value in values {
    let locale = Locale::parse(value) catch { _ => continue }
    push_unique_locale(locales, locale)
  }
  locales
}

///|
#doc(hidden)
pub fn posix_locale_candidates(value : String) -> Array[String] {
  value
  .split(":")
  .filter_map(fn(candidate) {
    posix_locale_candidate(candidate.trim().to_owned())
  })
  .to_array()
}

///|
fn posix_locale_candidate(value : String) -> String? {
  guard !value.is_empty() else { return None }
  let without_encoding = match value.split_once(".") {
    Some((prefix, _)) => prefix.to_owned()
    None => value
  }
  let without_modifier = match without_encoding.split_once("@") {
    Some((prefix, _)) => prefix.to_owned()
    None => without_encoding
  }
  match without_modifier.to_upper() {
    "C" | "POSIX" => None
    _ => Some(without_modifier.replace_all(old="_", new="-"))
  }
}

///|
fn push_unique_locale(values : Array[Locale], locale : Locale) -> Unit {
  if !values.contains(locale) {
    values.push(locale)
  }
}
