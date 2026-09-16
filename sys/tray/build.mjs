#!/usr/bin/env node

process.stdout.write(JSON.stringify({
  link_configs: process.platform === "darwin"
    ? [{ package: "moonbit-community/proton_tray", link_flags: "-Wl,-needed_framework,AppKit" }]
    : [],
}));
