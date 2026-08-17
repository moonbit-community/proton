# Internal Native Runtime Migration

This document is the temporary execution checklist for moving Proton's native
runtime from a separately built dynamic library into the
`moonbit-community/proton` module. Delete this document after every item is
implemented and the final validation passes.

## Target Architecture

```text
moonbit-community/proton
  internal/native/ffi    raw private FFI and platform stubs
  internal/native        MoonBit ownership, state, events, and errors
  internal/cef_process   dedicated CEF subprocess executable
  extension              public extension capabilities
  <root package>         public application facade
```

Proton code is compiled directly into each application executable. CEF remains
a dynamically loaded platform runtime. No Proton dynamic library, public C ABI,
native prebuilt, or compatibility package remains.

## Invariants

- One process owns at most one active native host and runtime.
- The process owner thread drives MoonBit async, the platform loop, and CEF.
- Native callbacks only enqueue C-owned records and wake the external loop.
- MoonBit owns config validation, lifecycle state, permissions, and errors.
- C and Objective-C own CEF calls, platform objects, thread affinity, and queues.
- Native objects use private external pointers with explicit owner-thread
  destruction. GC finalizers never destroy CEF or UI objects.
- Asynchronous operations use request, completion, and cancellation records.
- Shutdown waits for every browser close completion before calling
  `cef_shutdown`; there are no timeout, `atexit`, or forced-close fallbacks.
- Project configuration remains JSON. JSON is removed only from the private
  MoonBit-to-native configuration boundary.
- Extensions consume semantic Proton capabilities, never native handles.
- `sys/*` modules are outside this migration.

## Execution Checklist

### 1. Source Build Foundation

- [x] Create `proton/internal/native/ffi` and `proton/internal/native`.
- [x] Move tracked native common and platform sources under the Proton module.
- [x] Compile the sources through MoonBit `native-stub` on all three platforms.
- [x] Restrict `native_link_config.mjs` to CEF include and link configuration.
- [x] Remove Proton library resolution and fallback paths.

### 2. Typed Internal Runtime

- [x] Replace runtime config JSON with MoonBit validation and typed FFI.
- [x] Replace window and view config JSON with typed FFI.
- [x] Replace bridge config JSON with typed FFI.
- [x] Replace menu config JSON with typed FFI.
- [x] Replace the global integer handle registry with private external pointers.
- [x] Add explicit host, runtime, window, and view lifecycle state.
- [x] Keep all CEF and UI operations on the owner thread.
- [x] Isolate native callback allocations from MoonBit's thread-local allocator.
- [ ] Translate private FFI failures into subsystem-specific MoonBit errors.

### 3. Events, Async Operations, and Shutdown

- [x] Preserve the existing MoonBit async external event loop integration.
- [ ] Replace native callback entry with one C-owned completion/event queue.
- [ ] Convert true asynchronous operations to request/completion/cancel.
- [ ] Remove subsystem polling loops, fixed sleeps, and timeout fallbacks.
- [ ] Implement strict browser-close-before-CEF-shutdown sequencing.

### 4. Public Facade and Extensions

- [ ] Make `App` and `@proton.run` the only public runtime entry.
- [ ] Move user-facing menu, window, view, screen, and error types to the facade.
- [ ] Remove public raw runtime, native handle, native error, and escape APIs.
- [x] Add an opaque command-window capability to `CommandContext`.
- [x] Migrate dialog and notification extensions to semantic capabilities.
- [x] Move native-only E2E coverage to facade black-box or internal tests.

### 5. CEF Process and CLI

- [x] Add `proton/internal/cef_process` as a MoonBit executable.
- [x] Resolve helper source identity from the application's Proton dependency.
- [x] Build the helper through the application's normal Moon build cache.
- [x] Update `doctor`; `cef setup`, `dev`, `build`, and `package` are complete.
- [x] Package only the app executable, matching helper, and CEF runtime.

### 6. Remove the Dynamic-Library Product

- [x] Delete `proton/native` and all compatibility exports.
- [x] Delete the standalone `native` CMake project and public C header.
- [x] Delete `proton/prebuilt`, manifests, source hashes, and ABI checks.
- [x] Delete prebuilt build and synchronization workflows.
- [x] Update maintainer and application documentation.

### 7. Validation

- [ ] Prefer MoonBit black-box facade tests over internal white-box tests.
- [ ] Retain white-box tests only for otherwise unobservable native invariants.
- [ ] Remove CTest and the parallel C smoke-test product.
- [ ] Build from source on macOS, Windows, and Linux CI.
- [ ] Run existing bridge, multi-window, extension, updater, and lifecycle E2E.
- [ ] Run real macOS dev and packaged application checks.
- [ ] Verify packaged executables have no Proton dynamic-library dependency.
- [ ] Run `moon fmt`, `moon info`, and all relevant MoonBit tests.
- [ ] Delete this document and commit the final cleanup.

## Non-Goals

- Redesigning the existing external event loop.
- Folding the separately published `sys/*` modules into Proton.
- Supporting multiple active CEF runtimes in one process.
- Preserving the public `proton/native` API or the public C ABI.
- Adding fallback, compatibility, timeout, or forced-cleanup paths.
