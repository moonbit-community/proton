#!/usr/bin/env node

process.stdout.write(JSON.stringify({
  link_configs: process.platform === "darwin"
    ? [{ package: "moonbit-community/proton_keepawake", link_flags: "-framework IOKit -framework CoreFoundation" }]
    : [],
}));
