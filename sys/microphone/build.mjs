#!/usr/bin/env node

process.stdout.write(JSON.stringify({
  link_configs: process.platform === "darwin"
    ? [{ package: "moonbit-community/proton_microphone", link_flags: "-framework CoreAudio -framework CoreFoundation" }]
    : [],
}));
