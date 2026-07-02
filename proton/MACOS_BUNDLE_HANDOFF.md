# Proton submodule + macOS bundle blank-page investigation — handoff

## Why proton lives in the desktop/lepus submodule

`justjavac/proton@0.1.6` (mooncakes) is consumed as a **local workspace member**
instead of the registry package. The working Proton implementation now lives in
the `desktop/lepus` submodule and is registered in `desktop/moon.work`
(`members = [".", "./lepus/proton"]`). Builds compile Proton from this tree;
edit it directly and push changes to the submodule branch.

- The CEF runtime itself (`Chromium Embedded Framework.framework`, libproton,
  cef_process) is **not** vendored — it is downloaded into `.proton/runtimes/...`
  (gitignored). `desktop/lepus/proton/prebuilt/` holds only the tiny
  per-platform glue the package ships.
- To re-sync with a newer registry release: re-extract the zip over
  `desktop/lepus/proton/`
  and re-apply the macOS changes below (or just the diff in `facade_macos_layout.mbt`
  + `native/types.mbt` + `facade_runtime.mbt`).

## The problem

The packaged macOS `.app` renders a **blank page**. Dev runs fine because the
project's only non-bundle path — `moon run` of the bare host — has no
`Contents/Info.plist`, so Chromium skips the bundle-only code-signing checks.
(There is no other "unpackaged" mode; the README dev flow is
`moon run package/macos` → `open dist/...app`, which is the bundle path.)

Two independent macOS-bundle-only blockers, in order:

### Blocker #1 — MachPortRendezvous BaseBundleID mismatch  → FIXED here

In a signed `.app`, Chromium names its IPC service
`<CFBundleIdentifier>.MachPortRendezvousServer.<pid>`. A bare `cef_process`
helper (no enclosing bundle) computes an **empty** base bundle id, looks up
`.MachPortRendezvousServer.<pid>`, gets `Unknown service name (1102)`, and every
child process terminates → blank page.

**Fix (implemented):** launch the helper from a nested helper `.app` under
`Contents/Frameworks/`. Chromium's outer-bundle walk then climbs out to the main
`.app` and yields the same base bundle id as the browser, so the names match.

- `native/types.mbt`: `RuntimeConfig::bundled` gains an optional `helper_path`
  (kept `use_bundled=true` so framework/resources discovery is unchanged).
- `facade_macos_layout.mbt` (new): `macos_bundled_helper_path()` detects
  `…/Contents/MacOS/<exe>` and returns the first `Contents/Frameworks/*.app`
  helper executable; `None` otherwise (dev / other platforms unaffected).
- `facade_runtime.mbt`: `run_manifest` passes that as `helper_path?`.

**Verified empirically:** with a hand-built `.app` whose `cef_process` lives in
`Contents/Frameworks/<name> Helper.app` (rpath up to `Resources/proton/lib`),
gpu + network + storage children spawn and persist, and the rendezvous lookup now
carries the correct full prefix. **This still needs to be wired into packaging**
(`package/macos/main.mbt`) — see "Remaining work".

### Blocker #2 — process_requirement self-validation (-67030)  → NOT solved

Once #1 is cleared, navigation triggers a renderer, but the **browser refuses to
spawn it** (no helper launch; `Inspector.targetCrashed`; page url stays empty).
Root cause logged by the browser:

```
base/mac/process_requirement.cc:165] Unable to derive validation category for
current process. Signature validation of current process failed:
Error … Code=-67030  (errSecCSInfoPlistFailed)
```

Chromium ≥ M147 gates this behind two features, **enabled** in this CEF build:
`MachPortRendezvousValidatePeerRequirements` (perform) and
`…EnforcePeerRequirements` (enforce). Even in validate-only mode the browser
aborts the renderer launch when it cannot derive its own validation category.

Deriving the category requires an **Apple anchor** in the signature
(`anchor apple generic and certificate …`, per the chromium embedder-dev thread
"macOS code signing changes … PWAs"). **Ad-hoc signing has no anchor**, so it can
never satisfy it. Confirmed dead ends (ad-hoc): plain adhoc, `--deep` adhoc,
`--deep` adhoc **with entitlements** (allow-jit / unsigned-exec-mem /
disable-library-validation), sealing the helper `.app` and main app, launch via
`open` vs direct exec. `codesign --verify --deep --strict` reports the bundle
*valid and satisfying its DR*, yet the runtime dynamic check still returns -67030.

## Two viable paths for blocker #2 (for whoever picks this up)

1. **Real Developer ID signature** (the legitimate distribution path). The
   embedder-dev guidance is to set `codesign_requirements_basic` /
   `codesign_requirements_outer_app` so the derived requirement matches. The
   user's lead — `codesign --force --deep --entitlements app.entitlements --sign
   <real-hash> …` — is expected to work with a **real identity**, not ad-hoc.
   Untestable here (no Developer ID identity on this machine). This is the most
   likely correct answer and pairs naturally with notarization.

2. **Disable the feature** via `--disable-features=MachPortRendezvousValidatePeerRequirements`
   (+ `…EnforcePeerRequirements`). **Promising and not yet fully chased:**
   - Confirmed the browser **does** honor this argv switch — passing it flips the
     value propagated to children from `1` (validate-only) to `0` (no validation).
     (Note: `--remote-debugging-port` is ignored because proton overrides it via
     config; that is NOT the same as `command_line_args_disabled`.)
   - The env var that carries the policy to children is
     `MACH_PORT_RENDEZVOUS_PEER_VALDATION` (Chromium's own typo): `0`=none,
     `1`=validate-only, `2`=enforce.
   - **Open question:** does flipping children to `0` (and/or the browser to
     no-validation) actually let the renderer launch, or does the browser-side
     `-67030` still abort it? When last tested the browser still logged -67030 and
     the renderer still didn't spawn — but the browser's own policy was not yet
     forced to 0 (only children were). Next step: get proton to pass
     `--disable-features=MachPortRendezvousValidatePeerRequirements,MachPortRendezvousEnforcePeerRequirements`
     into the **browser's** CEF command line (via `OnBeforeCommandLineProcessing`
     in libproton's C++, or check whether libproton already forwards a config /
     env hook). proton sets `command_line_args_disabled`, so a switch the host
     puts on argv that proton doesn't explicitly clear is the lever to verify.

## Remaining work

- Wire the canonical Helper.app layout into `package/macos/main.mbt`:
  create `Contents/Frameworks/<name> Helper.app/Contents/MacOS/cef_process`
  (copy of the runtime's cef_process), add rpath
  `@loader_path/../../../../Resources/proton/lib`, write a Helper Info.plist
  (`CFBundleIdentifier = <app id>.helper`), re-sign the helper exe ad-hoc keeping
  `-i cef_process`. The runtime stays under `Resources/proton` as today.
- Resolve blocker #2 via path 1 or 2 above.
- Re-validate linux/windows packaging (the facade change is macOS-gated and a
  no-op elsewhere, but confirm).

## How to reproduce / test cheaply

- Build: `moon build frontend --target js --release` then copy
  `_build/js/release/build/openseek_desktop/frontend/frontend.js`, and
  `moon build . --target native --release`.
- Stage `index.html` + `frontend.js` under `<exe-dir>/assets/`.
- Hand-assemble a `.app` (host at `Contents/MacOS/openseek-desktop`, runtime at
  `Contents/Resources/proton`, helper at `Contents/Frameworks/<name> Helper.app`),
  repoint the host rpath to `@executable_path/../Resources/proton/lib`, ad-hoc sign.
- Run with `PROTON_CEF_LOG=1`; inspect via CDP on `127.0.0.1:9222`
  (`/json/list`, force `Page.navigate` to a `data:` URL and watch for
  `Inspector.targetCrashed`). The minimal CEF build suppresses verbose/VLOG and
  os_log, so rely on ERROR-level lines, `ps` for `--type=renderer`, and
  `~/Library/Logs/DiagnosticReports/cef_process*.ips` (note: macOS throttles
  repeated identical crashes).
