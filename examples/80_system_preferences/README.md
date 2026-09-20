# System Preferences

This is a manual review example for Proton's Electron-style system preference
queries: `system_accent_color()`, `system_animation_settings()`,
`system_media_access_status`, and `system_is_trusted_accessibility_client`.

Run it with:

```sh
moon -C examples run 80_system_preferences --target native
```

The page reads every query once at startup and re-reads them when you press
**Re-read all values**. Nothing in this example changes system state, so the
only cleanup is closing the window. The macOS prompt button registers the
application with Accessibility settings; remove it there if you tried it.

## Review steps

1. Compare the accent swatch and its RGBA digits with the accent color of this
   machine. Windows: **Settings → Personalization → Colors → Accent color**.
   macOS: **System Settings → Appearance → Accent color**. Change the accent
   color, press **Re-read all values**, and the swatch and digits should follow.
   A platform without an accent color reports `(no accent color)`.
2. Compare **shouldRenderRichAnimation** and **prefersReducedMotion** with the
   animation setting. Windows: **Settings → Accessibility → Visual effects →
   Animation effects**. macOS: **System Settings → Accessibility → Display →
   Reduce motion**. Turn animations off, press **Re-read all values**, and the
   values should flip while the green marker freezes.
3. Compare the three media rows with the privacy settings. Windows:
   **Settings → Privacy & security → Microphone / Camera**. macOS:
   **System Settings → Privacy & Security → Microphone / Camera / Screen
   Recording**. The values are Electron's vocabulary: `not-determined`,
   `granted`, `denied`, `restricted`, or `unknown`.
4. On macOS, press **Check silently**. The row reports whether this process is
   a trusted accessibility client. Press **Check with prompt** to pass
   `prompt: true`: macOS opens its own dialog and adds the application to the
   Accessibility list. Grant or deny it there, then press **Check silently**
   again and confirm the row follows the setting.
5. Every query that this platform does not answer is listed under **Platform
   errors** with the status code Proton returned, so the platform matrix is
   visible without reading the source.

## Platform matrix

| Query | Windows | macOS | Linux |
| --- | --- | --- | --- |
| `system_accent_color()` | DWM accent value | control accent color | empty (no desktop portal read yet) |
| `system_animation_settings()` | `SPI_GETCLIENTAREAANIMATION` and the remote-session fallback | reduce motion and `NSScrollAnimationEnabled` | GTK `gtk-enable-animations`, otherwise enabled |
| `system_media_access_status()` | consent store for microphone and camera, granted for screen | AVFoundation authorization, screen recording preflight | unsupported error |
| `system_is_trusted_accessibility_client()` | unsupported error | `AXIsProcessTrustedWithOptions` | unsupported error |

## Electron parity notes

The accent color is reported as RGBA hexadecimal digits without a leading `#`,
which is what `systemPreferences.getAccentColor()` returns. Windows discards the
stored alpha exactly like Electron, because Electron converts the DWM value
through a `COLORREF`; macOS keeps the color's own alpha. An empty accent color
is not an error on either platform.

`getColor`, `getSystemColor`, `askForMediaAccess`, the macOS notification
subscriptions, and the `accent-color-changed` / `color-changed` events are not
part of this slice. The change events need the platform notification sources;
query again after changing a setting until they land.
