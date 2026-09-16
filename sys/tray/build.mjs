#!/usr/bin/env node

import { execFileSync } from "node:child_process";

process.stdout.write(JSON.stringify({
  link_configs: process.platform === "darwin"
    ? [{ package: "moonbit-community/proton_tray", link_flags: "-Wl,-needed_framework,AppKit" }]
    : process.platform === "linux"
      ? [{
          package: "moonbit-community/proton_tray",
          link_flags: execFileSync("pkg-config", ["--libs", "gtk+-3.0"], { encoding: "utf8" }).trim() + " -ldl",
        }]
      : [],
  vars: { LINUX_STUB_FLAGS: process.platform === "linux" ? execFileSync("pkg-config", ["--cflags", "gtk+-3.0"], { encoding: "utf8" }).trim() : "" },
}));
