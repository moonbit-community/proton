#!/usr/bin/env node

process.stdout.write(JSON.stringify({
  link_configs: process.platform === "darwin"
    ? [{ package: "moonbit-community/proton_safe_storage", link_flags: "-framework Security" }]
    : [],
}));
