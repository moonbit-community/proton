# macOS native capture regression

Requires macOS 14 or later, a graphical login session, Screen Recording
permission for the capture helper, Node.js with built-in WebSocket support,
Xcode command line tools, and this release's installed CEF runtime.

Run deliberately while the desktop is idle. The test covers a window, activates
a separate native application, and optionally switches Spaces. It is not part
of headless CI:

```sh
node e2e/repro_occlusion/run.mjs
# Also create and leave a fullscreen Space for the cover window:
node e2e/repro_occlusion/run.mjs --other-space
```

The runner builds the fixture and CEF subprocess from the current source. For
each of the default and opt-in configurations it paints a red then green marker
through CDP and captures the actual native window through ScreenCaptureKit.
No focus emulation or command-line rendering override is used. The opaque cover
must precede and completely contain the target in the native window list;
the other-Space mode requires the target to be offscreen. Assertions check fresh
capture pixels and advancing animation frames with the option enabled, real
page blur, Page Visibility in both modes, and recovery after minimize/hide.
The default control records screenshots without requiring resource reclamation
to happen identically on every macOS release.

The artifact directory contains app logs, PNG captures and `result.json`.
Failed placement or missing capture permissions fail the test; they are not
treated as a passing rendering check. Processes are isolated and stopped on
completion or interruption. The test does not assert continuous rendering of
minimized or explicitly hidden windows.
