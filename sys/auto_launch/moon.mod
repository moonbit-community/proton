name = "moonbit-community/auto_launch"

version = "0.1.3"

readme = "README.md"

repository = "https://github.com/moonbit-community/proton/tree/main/sys/auto_launch"

license = "Apache-2.0"

keywords = [
  "desktop",
  "autostart",
  "startup",
  "auto-launch",
  "native",
  "windows",
  "macos",
  "linux",
]

description = "Cross-platform auto-launch helpers for MoonBit, inspired by Teamwork/node-auto-launch."

warnings = ""

preferred_target = "native"

source = "."

options(
  supported_targets: "+native",
)
