#!/usr/bin/env node

process.stdout.write(JSON.stringify({
  link_configs: process.platform === "darwin"
    ? [{ package: "moonbit-community/proton_screen_monitor", link_flags: "-framework CoreGraphics -framework CoreFoundation" }]
    : process.platform === "win32"
      ? [{ package: "moonbit-community/proton_screen_monitor", link_flags: "shcore.lib user32.lib gdi32.lib" }]
      : [],
}));
