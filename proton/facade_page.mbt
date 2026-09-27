///|
fn NavigationTransition::from_code(code : Int) -> NavigationTransition {
  match code {
    0 => Link
    1 => Typed
    2 => AutoBookmark
    3 => AutoSubframe
    4 => ManualSubframe
    5 => Generated
    6 => AutoToplevel
    7 => FormSubmit
    8 => Reload
    9 => Keyword
    10 => KeywordGenerated
    other => Other(other)
  }
}

///|
/// Expands Chromium's transition qualifier flags. The flag values match the
/// engine's private encoding; an unknown flag adds no qualifier.
fn NavigationTransitionQualifier::from_flags(
  flags : Int,
) -> Array[NavigationTransitionQualifier] {
  let qualifiers : Array[NavigationTransitionQualifier] = []
  if (flags & 1) != 0 {
    qualifiers.push(ClientRedirect)
  }
  if (flags & 2) != 0 {
    qualifiers.push(ServerRedirect)
  }
  if (flags & 4) != 0 {
    qualifiers.push(ForwardBack)
  }
  if (flags & 8) != 0 {
    qualifiers.push(FromAddressBar)
  }
  qualifiers
}

///|
fn NavigationEntry::from_native(
  entry : @native.NavigationEntry,
) -> NavigationEntry {
  {
    url: entry.url,
    display_url: entry.display_url,
    original_url: entry.original_url,
    title: entry.title,
    transition: NavigationTransition::from_code(entry.transition),
    transition_qualifiers: NavigationTransitionQualifier::from_flags(
      entry.qualifiers,
    ),
    has_post_data: entry.has_post_data,
    http_status_code: entry.http_status_code,
  }
}

///|
fn NavigationHistory::from_native(
  history : @native.NavigationHistory,
) -> NavigationHistory {
  {
    entries: history.entries.map(entry => NavigationEntry::from_native(entry)),
    active_index: history.active_index,
  }
}

///|
/// Returns the number of entries in the snapshot.
pub fn NavigationHistory::length(self : NavigationHistory) -> Int {
  self.entries.length()
}

///|
/// Returns the entry at `index`, or `None` when the index is outside the
/// snapshot.
pub fn NavigationHistory::entry_at(
  self : NavigationHistory,
  index : Int,
) -> NavigationEntry? {
  guard index >= 0 && index < self.entries.length() else { return None }
  Some(self.entries[index])
}

///|
/// Returns the entry the browser is currently showing, or `None` when the
/// snapshot has no active entry.
pub fn NavigationHistory::active_entry(
  self : NavigationHistory,
) -> NavigationEntry? {
  self.entry_at(self.active_index)
}

///|
/// Reports whether a previous entry exists, matching Electron's
/// `navigationHistory.canGoBack()`.
pub fn NavigationHistory::can_go_back(self : NavigationHistory) -> Bool {
  self.active_index > 0
}

///|
/// Reports whether a later entry exists, matching Electron's
/// `navigationHistory.canGoForward()`.
pub fn NavigationHistory::can_go_forward(self : NavigationHistory) -> Bool {
  self.active_index >= 0 && self.active_index + 1 < self.entries.length()
}
