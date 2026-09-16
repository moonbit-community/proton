#!/usr/bin/env node

import { execFileSync } from "node:child_process";

process.stdout.write(JSON.stringify({
  link_configs: process.platform === "darwin"
    ? [{ package: "moonbit-community/proton_global_hotkey", link_flags: "-framework ApplicationServices -framework CoreFoundation" }]
    : process.platform === "linux"
      ? [{
          package: "moonbit-community/proton_global_hotkey",
          link_flags: execFileSync("pkg-config", ["--libs", "x11 >= 1.7"], { encoding: "utf8" }).trim(),
        }]
      : [],
  vars: { LINUX_STUB_FLAGS: process.platform === "linux" ? execFileSync("pkg-config", ["--cflags", "x11 >= 1.7"], { encoding: "utf8" }).trim() : "" },
}));
