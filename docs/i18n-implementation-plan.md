# Proton Locale Integration Plan

> Temporary implementation document. Delete this file after every phase below
> is implemented and the final validation matrix passes.

Source implementation and macOS runtime verification are complete. The final
cross-platform prebuilt rebuild and CI validation in phase 8 remain pending.

## Objective

Give Proton applications one deterministic, immutable application locale that
is shared by the MoonBit backend, CEF, native framework-owned UI, and command
contexts.

Proton owns platform locale discovery and propagation. Application authors own
their translation catalogs, message formatting, language preference storage,
and renderer updates.

## Non-goals

- Do not add a translation catalog or message lookup API.
- Do not define interpolation, plural, date, number, or currency formatting.
- Do not add a Rabbita-specific localization layer.
- Do not add locale configuration to `proton.project.json`.
- Do not support changing the application locale while a runtime is active.
- Do not localize `proton_cli`, logs, error codes, or developer diagnostics.
- Do not prune CEF locale resources or include locale selection in the runtime
  cache key.
- Do not inject JavaScript to override `navigator.language` or
  `navigator.languages`.

## Invariants

1. The application locale is resolved before native runtime creation and is
   immutable for the lifetime of that runtime.
2. One runtime has one locale shared by every window, view, lifecycle hook, and
   command request.
3. Display labels never carry structural identity. Menu semantics are expressed
   only by typed roles.
4. Native platform code never invents, translates, or infers visible labels.
5. CEF receives locale state through supported settings and command-line APIs,
   never through renderer bootstrap patches.
6. Explicit invalid locale input is a configuration error. Failure to query the
   operating system locale is recoverable and falls back to `en-US`.
7. Application-owned strings are localized by the application before they are
   passed to dialogs, notifications, custom menus, or page content.

## Locale Model

Create a pure MoonBit package at `proton/internal/locale`. The Proton root facade
re-exports the public locale types so application code uses `@proton.Locale`
rather than importing the internal package.

### `Locale`

`Locale::parse` implements RFC 5646 syntax, including grandfathered tags,
extensions, and private-use tags.

Canonical representation uses:

- lowercase language subtags;
- title-case script subtags;
- uppercase region subtags;
- lowercase variant, extension, and private-use subtags;
- `-` as the only accepted public separator.

Do not perform CLDR alias replacement. For example, accepting `i-klingon` does
not imply rewriting it to `tlh`. Public parsing rejects POSIX forms such as
`en_US.UTF-8`.

The initial public surface is:

```moonbit
pub fn Locale::parse(source : String) -> Locale raise LocaleParseError
pub fn Locale::to_string(self : Locale) -> String
pub fn Locale::language(self : Locale) -> String
pub fn Locale::script(self : Locale) -> String?
pub fn Locale::region(self : Locale) -> String?
```

`LocaleParseError` is a precise suberror covering at least empty input, invalid
characters, invalid subtag ordering, duplicate extensions, and overlong
subtags. Canonically equivalent locales compare equal.

### Resolved Preferences

Use one immutable internal value:

```moonbit
struct LocalePreferences {
  locale : Locale
  preferred_languages : Array[Locale]
}
```

Resolution order is:

1. an explicit `App::locale(Locale)`, when present;
2. valid operating-system preferred languages in platform order;
3. `en-US`.

An explicit locale is prepended to the system list. Canonical duplicates are
removed while preserving order. `en-US` is appended if it is not already
present. The first entry is the application locale.

Extensions and private-use subtags remain part of the application locale and
the Accept-Language preference list. They are removed only when deriving the
locale passed to Chromium UI localization and Proton's built-in catalog.

## Public Facade

Add:

```moonbit
pub fn system_preferred_languages(
) -> Array[Locale] raise SystemLocaleError

pub fn App::locale(self : App, locale : Locale) -> App
```

`system_preferred_languages` is runtime-independent and may be called before
constructing an `App`. Direct callers receive `SystemLocaleError` on a platform
query failure. Automatic application startup catches that error, records a
developer diagnostic, and resolves to `en-US`.

Expose the immutable startup snapshot through:

```moonbit
pub fn ApplicationContext::locale(self : ApplicationContext) -> Locale
pub fn ApplicationContext::preferred_languages(
  self : ApplicationContext,
) -> Array[Locale]

pub fn WindowContext::locale(self : WindowContext) -> Locale
pub fn WindowContext::preferred_languages(
  self : WindowContext,
) -> Array[Locale]

pub fn CommandContext::locale(self : CommandContext) -> Locale
pub fn CommandContext::preferred_languages(
  self : CommandContext,
) -> Array[Locale]
```

Do not provide a global current-application locale. Context getters return
copies where necessary and never re-query the operating system.

## Native Platform Query

Add one runtime-independent C ABI query that returns an ordered UTF-8 JSON
array using the existing caller-owned-buffer convention. The MoonBit wrapper
must retry when native reports that the supplied buffer is too small; a single
length probe followed by one unchecked read is not sufficient.

Platform implementations only collect platform values:

- macOS: `NSLocale.preferredLanguages`;
- Windows: `GetUserPreferredUILanguages`;
- Linux: `LANGUAGE`, otherwise the first non-empty value of `LC_ALL`,
  `LC_MESSAGES`, and `LANG`.

Linux converts POSIX locale syntax only inside the platform adapter: split a
colon-separated `LANGUAGE`, strip encoding and modifier suffixes, and replace
`_` with `-`. `C` and `POSIX` produce no locale candidate. MoonBit owns BCP 47
validation, canonicalization, deduplication, and fallback.

The query is synchronous, runtime-independent, and safe before CEF or window
initialization.

## CEF Integration

Extend the typed runtime config and all three native config parsers with:

- `locale`: the application locale with extensions and private-use removed;
- `accept_languages`: the complete ordered preference list.

Synchronize the new schema and prebuilt libraries on all three platforms. Do
not add compatibility fallback for old prebuilts that reject the new fields.

Configure CEF as follows:

- set global `CefSettings.accept_language_list` to a comma-delimited list with
  no whitespace or hand-written `q=` weights;
- set `CefSettings.locale` on macOS and Windows;
- append `--lang=<locale>` through CEF command-line processing on Linux because
  CEF ignores `CefSettings.locale` there;
- do not modify process `LANGUAGE` or `LC_*` variables;
- do not scan or interpret Chromium `.pak`/`.lproj` files;
- let Chromium own internal resource matching and fallback.

Validate the contract at the observable boundary: `navigator.language`,
`navigator.languages`, and the HTTP `Accept-Language` request header. Proton
does not claim to report which internal Chromium locale resource was selected.

## Menu Model

Replace all label-based semantic inference with typed roles.

### Public Types

Add:

```moonbit
enum MenuRole {
  Application
  File
  Edit
  View
  Window
  Help
}

enum MenuItemRole {
  Quit
  Hide
  HideOthers
  ShowAll
  Close
  Minimize
  Zoom
  Undo
  Redo
  Cut
  Copy
  Paste
  SelectAll
}
```

Use these constructors:

```moonbit
pub fn Menu::new(label : String, items~ : Array[MenuItem]) -> Menu
pub fn Menu::role(
  role : MenuRole,
  label? : String,
  items? : Array[MenuItem],
) -> Menu
pub fn MenuItem::role(
  role : MenuItemRole,
  label? : String,
  key? : String,
) -> MenuItem
```

Do not keep string-role overloads. Update every repository caller to the enum
API.

`MenuBar::new` describes the complete logical menu bar. Proton may insert a
platform-required Application menu when absent, but it must not silently append
Edit or Window menus. A custom menu named `Edit` remains custom and never
suppresses `MenuRole::Edit`.

When a standard menu omits `items`, defaults are:

- Application: Hide, Hide Others, Show All, separator, Quit;
- Edit: Undo, Redo, separator, Cut, Copy, Paste, Select All;
- Window: Minimize, Zoom, Close;
- File, View, Help: empty.

Supplying `items` replaces the default list exactly. Supplying a standard role
label or item label overrides localization exactly.

### Resolution and Native Rendering

Resolve the complete menu in MoonBit before calling native code:

- localize omitted standard labels using the application locale;
- interpolate the application name into Application-menu labels;
- preserve explicit labels and all custom command labels;
- serialize stable top-level and item role identifiers alongside final labels.

The initial private framework catalog supports `en-US` and `zh-CN`; unsupported
catalog locales fall back to English. Store the complete catalog as compile-time
MoonBit data and test key completeness. Do not package a runtime translation
file.

Remove native default menu creation, English fallback labels, and comparisons
against `Edit`, `Window`, or any other display string. Native uses top-level
roles for platform integration such as `setWindowsMenu` and item roles for
selectors/actions. It rejects visible entries that reach it without a final
label.

The facade submits a fully resolved initial menu after runtime creation and
before any window creation. Future menu updates must pass through the same
resolver.

## Framework-owned Failure UI

Localize framework-owned user-facing shells, initially:

- application startup failure title and generic summary;
- window/application error title and generic summary.

Keep dynamic technical details, paths, native errors, bridge diagnostics, logs,
and error codes in English. The localized generic summary precedes the original
technical detail. Controls drawn by Proton use the framework catalog for the
resolved application locale. Operating-system-owned controls continue to follow
the OS UI language.

Do not attempt to force `NSOpenPanel`, Windows common dialogs, or equivalent
system UI into an application override locale.

## Implementation Phases

### 1. Pure Locale Domain

- Add `proton/internal/locale`.
- Implement RFC 5646 parsing, canonicalization, equality, preference
  resolution, POSIX candidate conversion helpers, and typed errors.
- Add black-box MoonBit tests through the intended public behavior.

Exit condition: locale parsing and preference resolution tests pass without any
native runtime.

### 2. Platform Discovery

- Add the C ABI declaration and caller-owned-buffer wrapper.
- Implement macOS, Windows, and Linux adapters.
- Add native tests for platform conversion and output shape.
- Re-export the public query from the root facade.

Exit condition: each platform builds the same symbol and MoonBit receives a
validated ordered locale list.

### 3. Application Session Propagation

- Add the explicit locale field to `App`.
- Resolve `LocalePreferences` before runtime creation.
- Thread the immutable value through runtime session, application lifecycle,
  window lifecycle, and command request contexts.
- Add the agreed context getters and facade tests.

Exit condition: every context observes the same immutable canonical values and
startup fallback is deterministic.

### 4. CEF Language Configuration

- Extend typed runtime config serialization and all native schema validators.
- Configure CEF locale and Accept-Language on all three engines.
- Configure Linux `--lang` without mutating locale environment variables.
- Add observable CEF/E2E coverage for JavaScript language values and HTTP
  headers.

Exit condition: backend preferences, renderer language values, and network
language headers agree.

### 5. Typed Menu Semantics

- Introduce `MenuRole` and `MenuItemRole` in the public facade.
- Migrate all repository callers away from string roles.
- Implement standard-menu defaults and full MoonBit menu resolution.
- Add complete `en-US` and `zh-CN` framework catalogs.
- Remove label comparisons, default synthesis, and visible fallback strings
  from macOS and Linux native menu implementations.
- Preserve stable semantic roles in the native wire representation.

Exit condition: changing a label cannot change menu behavior, omitted role
labels are localized, and native code contains no framework menu translations.

### 6. Failure UI Localization

- Resolve framework failure text from the same immutable locale preferences.
- Localize the generic user-facing shell while preserving technical detail.
- Test supported-locale output and English fallback.

Exit condition: `en-US` and `zh-CN` failure dialogs have localized shells and
identical underlying diagnostics.

### 7. Example and Documentation

- Add a focused i18n example showing backend locale values,
  `navigator.languages`, and the Chinese standard menu.
- Update the example index and public facade/menu documentation.
- State explicitly that application translation catalogs remain application
  responsibility.

Exit condition: the example demonstrates only Proton's platform contract and
does not contain a framework translation engine.

### 8. Cross-platform Artifacts and Validation

- Run `moon fmt` and `moon info`.
- Run pure MoonBit locale and facade tests.
- Run native CMake/CTest validation.
- Build examples and E2E packages.
- Perform macOS CEF runtime verification for JavaScript and HTTP language
  behavior.
- Manually verify the Chinese menu and localized startup failure shell.
- Build Windows and Linux implementations in CI.
- Rebuild and synchronize all three prebuilt artifacts and headers.
- Run generated-source and prebuilt ABI verification.

Exit condition: all local applicable checks and remote platform builds pass,
and the macOS human-visible behavior is accepted.

### 9. Remove This Plan

Delete `docs/i18n-implementation-plan.md` only after phases 1-8 are complete.
The durable API and behavior belong in public package documentation, tests, and
maintainer guidance rather than this temporary implementation checklist.
