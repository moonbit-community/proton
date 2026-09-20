# macOS fullscreen / close reproduction

## Run

Requires macOS with a graphical login session, the MoonBit toolchain, Node.js,
and this release's installed CEF runtime. If needed, install the runtime first:

```sh
PROTON_CEF_SETUP_BOOTSTRAP=1 moon -C cefsetup run . --target native -- --runtime-only
```

From the repository root:

```sh
node e2e/repro_fullscreen_close/run.mjs
```

The runner builds a small app and a helper from the current source. It starts
one isolated process group, records the result after at most 20 seconds, and
kills any remaining processes in that group on completion or interruption.
It prints an artifact directory containing `app.log`, `result.json`, and the
helper used by that run. No remote debugging port or external UI automation
is required.

The app performs:

1. Create an Overlay window using the system button positions.
2. Enter fullscreen and wait three seconds for the transition.
3. Exit fullscreen and wait three seconds for the transition.
4. Evaluate `window.close()` in the page.

For comparison, skip the fullscreen round trip:

```sh
node e2e/repro_fullscreen_close/run.mjs --direct-close
```

Exercise the other fullscreen exit paths:

```sh
node e2e/repro_fullscreen_close/run.mjs --restore
node e2e/repro_fullscreen_close/run.mjs --kiosk
```

`--restore` enters fullscreen normally and exits through `WindowHandle::restore`.
`--kiosk` enters and exits through `WindowHandle::set_kiosk`. Each fullscreen
mode verifies that the window entered and left fullscreen before closing.

The fixed waits make the sequence easy to inspect; this is a diagnostic
reproduction, not proof of identical animation timing on every Mac.

## Expected and observed behavior

Expected: the window closes, the application exits with code 0, and its helpers
exit. The runner returns 0 only when these conditions hold.

Observed during investigation on macOS: fullscreen return followed by closing
can report:

```text
runtime failed during poll event (-2): window is not initialized
```

The application and CEF helpers can remain alive. The runner returns 1 for a
failure and records the process group **before** forced cleanup; forced cleanup
must not be interpreted as successful application shutdown. `matchingError`
distinguishes this exact error from other failures or a timeout. MoonBit stdout
can remain buffered in the hung process, so missing progress lines alone do not
prove that a step was not reached.

## Child-browser shutdown regression (#316)

These commands open real windows. Run them deliberately in a graphical session;
do not run them during unrelated desktop work. The existing runner checks both
normal application return and the absence of remaining helper processes before
any forced cleanup.

```sh
# No-child control, then one and two live child browsers.
node e2e/repro_fullscreen_close/run.mjs --direct-close --native-close
node e2e/repro_fullscreen_close/run.mjs --direct-close --native-close --views=1
node e2e/repro_fullscreen_close/run.mjs --direct-close --native-close --views=2 --show-inactive
# Close children first; re-show through focus instead of show.
node e2e/repro_fullscreen_close/run.mjs --direct-close --native-close --views=2 --refocus --close-child-first
# Combine child ownership with fullscreen transitions and renderer close.
node e2e/repro_fullscreen_close/run.mjs --views=1
```

Children use static data URLs. The application waits for all children to load
before exercising the selected operations. `--native-close` calls the public
`WindowHandle::close` API; without it, closing originates in the main renderer.
The runner accepts the same child options with `--restore` and `--kiosk`.
