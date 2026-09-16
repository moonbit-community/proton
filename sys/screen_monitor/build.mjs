#!/usr/bin/env node

import { execFileSync } from "node:child_process";

process.stdout.write(JSON.stringify({
  link_configs: process.platform === "darwin"
    ? [{ package: "moonbit-community/proton_screen_monitor", link_flags: "-framework CoreGraphics -framework CoreFoundation" }]
    : process.platform === "win32"
      ? [{ package: "moonbit-community/proton_screen_monitor", link_flags: "shcore.lib user32.lib gdi32.lib" }]
      : process.platform === "linux"
        ? [{
            package: "moonbit-community/proton_screen_monitor",
            link_flags: execFileSync("pkg-config", ["--libs", "x11", "xrandr >= 1.5"], { encoding: "utf8" }).trim(),
          }]
        : [],
  vars: { LINUX_STUB_FLAGS: process.platform === "linux" ? execFileSync("pkg-config", ["--cflags", "x11", "xrandr >= 1.5"], { encoding: "utf8" }).trim() : "" },
}));
