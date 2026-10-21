#!/usr/bin/env node

process.stdout.write(JSON.stringify({
  link_configs: process.platform === "darwin"
    ? [{ package: "moonbit-community/proton_clipboard", link_flags: "-framework AppKit" }]
    : [],
  vars: { MACOS_STUB_FLAGS: process.platform === "darwin" ? "-ObjC" : "" },
}));
