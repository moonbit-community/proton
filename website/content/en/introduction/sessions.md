# Browser sessions

A browser session contains cookies, cache, authentication state and web storage. Obtain its handle from `window.browser().session()`. A handle is reached through a browser, but clearing shared session data is not a private operation on that one page.

## Startup settings

`App.session_partition(name)` selects a persistent profile below the application's sessionData directory. It is application startup configuration, not a per-window incognito switch. Windows in the application runtime use that configured profile. Use stable application identifiers and partition names to preserve data across launches.

`App.proxy(server, bypass?)` configures Chromium's startup-wide proxy. It cannot be changed during the run. This controls browser traffic; it does not configure every MoonBit networking library in the host.

The `on_session_created` callback exposes the partition and resolved data path before application start hooks create their windows. Packaged resources and the browser profile are different paths; do not put writable profile data inside the application bundle.

## Operations

| API | Effect |
| --- | --- |
| `get_cookies` | Asynchronously reads matching cookies; optional URL and HttpOnly selection |
| `set_cookie` | Sets a cookie with URL, name, value and optional domain/path/security attributes |
| `delete_cookies`, `flush_cookies` | Deletes selected cookies or flushes persistent cookie storage |
| `clear_cache`, `clear_storage_data` | Clears cache or selected web-storage kinds |
| `clear_auth_cache` | Clears cached HTTP authentication |
| `clear_certificate_exceptions` | Clears certificate exception state |
| `close_all_connections` | Closes session connections |

Operations can fail when the owning browser/window is no longer usable. Await cookie reads inside a live lifecycle scope. A clearing operation does not erase application-owned files or implement an application logout protocol; invalidate backend credentials and UI state separately.

Full attributes and `StorageDataKind` variants are in the [API reference](https://mooncakes.io/docs/moonbit-community/proton@0.3.4/).
