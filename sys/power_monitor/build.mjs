#!/usr/bin/env node

process.stdout.write(JSON.stringify({
  link_configs: process.platform === "darwin"
    ? [{ package: "moonbit-community/proton_power_monitor", link_flags: "-framework CoreGraphics -framework IOKit -framework CoreFoundation" }]
    : [],
  vars: { MACOS_STUB_FLAGS: process.platform === "darwin" ? "-fblocks" : "" },
}));
