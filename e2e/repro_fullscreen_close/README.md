# macOS fullscreen / close reproduction

This branch starts from main `850b4564` (Proton 0.2.10). The reproduction does not use traffic
light positioning from PR #304. On the fix branch, it also serves as a
regression test for the repaired native lifecycle.

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

Verified on 2026-09-15 with this reproduction on `850b4564`:

| Mode | Result |
| --- | --- |
| Fullscreen round trip | Exact error reproduced; parent and five helpers still alive at the 20-second deadline; runner returned 1 and cleaned its process group. |
| Direct close | Application exited with code 0; no process-group members remained; runner returned 0. |

These observations are individual runs, not a measured failure rate.

## Source-level diagnosis

`proton_engine_window_commit_appkit_close` clears `window->window` and sets
`appkit_closing`, while `closed` is still false until CEF's completion callback.
`proton_runtime_sync_engine_window_states` skips closed windows but can still
call `proton_engine_window_get_state` during this intermediate state. The latter
returns `PROTON_ERR_INVALID_HANDLE` (-2) because the native window is gone.
The facade promotes that result to an application-level polling failure.

Earlier diagnostic instrumentation captured `detach closed=0 appkit_closing=1`,
then `get_state closed=0 appkit_closing=1`, followed by the error and only later
`mark_closed`. The same error was reproduced on main before PR #304.
Temporarily bypassing the invalid state read removed the error but did not make
the process exit in a separate experiment. Eliminating this message alone is
therefore insufficient evidence that window/CEF cleanup has been repaired.

## Fix

Window actions, including all three `toggleFullScreen:` paths, use a local
autorelease pool. These
synchronous FFI calls occur outside the event-pump pool; temporary AppKit
references created during fullscreen otherwise keep the CEF host view alive
past native window closure. The browser then cannot complete its close and
subprocess shutdown remains pending.

Native-window closure is also recognized when the AppKit window pointer is
cleared, so state polling does not access a window that has already gone away.
This does not bypass CEF teardown: browser finalization still waits for the
independent browser lifecycle to reach its terminal state.

The macOS CI job runs fullscreen, restore, and kiosk modes. The existing
windowed-close test and `--direct-close` provide non-fullscreen controls.

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

The window and view native entry points now scope their AppKit/CEF temporary
objects with autorelease pools, including synchronous display operations.
Fullscreen uses that same operation boundary. Host handles remain borrowed:
closing detaches them without an extra release of an unowned reference.
