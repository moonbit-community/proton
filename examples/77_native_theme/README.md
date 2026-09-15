# System Appearance

Run `moon -C examples run 77_native_theme --target native`.

The example reads system appearance and subscribes to changes. The window theme
buttons control only native chrome. The page media query follows the system.

1. Verify the initial read shows the system color scheme and contrast.
2. Choose Light and Dark window themes. The system summary must remain unchanged,
   and no system-change event should appear. System restores the window default.
3. Change the operating system appearance. The summary and page media query
   should follow; a forced window theme should remain forced.
4. Change the system contrast option and check the captured event snapshot.
5. Read back explicitly; the read itself must not emit a system-change event.

Linux uses GTK settings; Windows event delivery requires a native window.

Linux does not support per-window Light/Dark overrides; those buttons report
the native unsupported error instead of changing system settings.
