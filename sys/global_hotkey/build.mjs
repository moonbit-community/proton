#!/usr/bin/env node

process.stdout.write(JSON.stringify({
  link_configs: process.platform === "darwin"
    ? [{ package: "moonbit-community/proton_global_hotkey", link_flags: "-framework ApplicationServices -framework CoreFoundation" }]
    : [],
}));
