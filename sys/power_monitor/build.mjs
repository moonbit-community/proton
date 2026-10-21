#!/usr/bin/env node

import { execFileSync } from "node:child_process";

process.stdout.write(JSON.stringify({
  link_configs: process.platform === "darwin"
    ? [{ package: "moonbit-community/proton_power_monitor", link_flags: "-framework CoreGraphics -framework IOKit -framework CoreFoundation" }]
    : [],
  vars: {
    MACOS_STUB_FLAGS: process.platform === "darwin" ? "-fblocks" : "",
    LINUX_STUB_FLAGS: process.platform === "linux"
      ? execFileSync("pkg-config", ["--cflags", "gio-2.0"], { encoding: "utf8" }).trim()
      : "",
  },
}));
