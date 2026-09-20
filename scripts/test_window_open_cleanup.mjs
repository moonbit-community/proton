#!/usr/bin/env node

// Inject one destroy failure in an isolated source copy, never in the runtime
// shipped to users. Exercise the existing headless public-API startup fixture.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const temporary = mkdtempSync(path.join(tmpdir(), "proton-window-cleanup-"));
function replace(file, before, after) {
  const destination = path.join(temporary, file);
  const source = readFileSync(destination, "utf8");
  assert.equal(source.split(before).length, 2, `expected one injection site in ${file}`);
  writeFileSync(destination, source.replace(before, after));
}
try {
  const files = spawnSync("git", ["ls-files", "-z"], { cwd: root, encoding: "utf8" });
  assert.equal(files.status, 0, files.stderr);
  for (const file of files.stdout.split("\0").filter(Boolean)) {
    const destination = path.join(temporary, file);
    mkdirSync(path.dirname(destination), { recursive: true });
    copyFileSync(path.join(root, file), destination);
  }
  const native = "proton/internal/native/native.mbt";
  replace(native, "  let status = @native_ffi.proton_window_destroy_ffi(self.handle)", `  cleanup_test_destroy_calls.val += 1
  if cleanup_test_destroy_calls.val == 1 {
    raise Status(status=-1, message="INJECTED_WINDOW_DESTROY_FAILURE")
  }
  let status = @native_ffi.proton_window_destroy_ffi(self.handle)`);
  writeFileSync(path.join(temporary, "proton/internal/native/cleanup_probe.mbt"), `///|
let cleanup_test_destroy_calls : Ref[Int] = Ref(0)
///|
pub fn cleanup_test_destroy_count() -> Int { cleanup_test_destroy_calls.val }
`);
  replace("proton/facade_lifecycle.mbt", "  for running in windows {", `  assert_eq(windows.length(), 1) catch { _ => abort("failed window was unregistered") }
  assert_true(windows[0].is_closed()) catch { _ => abort("window was not marked closed") }
  assert_eq(@native.cleanup_test_destroy_count(), 1) catch { _ => abort("missing first destroy attempt") }
  for running in windows {`);
  replace("proton/facade_lifecycle.mbt", "  let failure_count = failures.length()", `  assert_eq(@native.cleanup_test_destroy_count(), 2) catch { _ => abort("cleanup did not retry") }
  assert_eq(windows[0].window.id(), 0L) catch { _ => abort("retry did not destroy window") }
  let failure_count = failures.length()`);

  const fixture = "examples/e2e_fixtures/lifecycle_regressions.mbt";
  replace(fixture, '  @proton.html("Startup cancellation",', '  let cancellation_seen = Ref(false)\n  try {\n  @proton.html("Startup cancellation",');
  replace(fixture, '  assert_true(main_ready.val)\n  assert_false(secondary_ready.val)', `  } catch {
    @proton.AppRunError::CleanupFailed(primary~, failures~) => {
      assert_eq(primary is Some(_), @env.get_env_var("CLEANUP_TEST_PRIMARY") == Some("1"))
      if primary is Some(message) { assert_true(message.contains("INJECTED_STARTUP_FAILURE")) }
      assert_eq(failures.length(), 1)
      assert_true(failures[0].message().contains("INJECTED_WINDOW_DESTROY_FAILURE"))
    }
    error => fail("unexpected application error: " + error.message())
  } noraise { _ => fail("destroy failure did not escape the session") }
  assert_false(main_ready.val)
  if @env.get_env_var("CLEANUP_TEST_PRIMARY") != Some("1") { assert_true(cancellation_seen.val) }`);
  replace(fixture, 'error => assert_true(@async.is_cancellation_error(error))', `error => {
          assert_true(@async.is_cancellation_error(error))
          cancellation_seen.val = true
        }`);
  const cancellationFixture = readFileSync(path.join(temporary, fixture), "utf8");
  for (const primary of [false, true]) {
    if (primary) {
      const start = cancellationFixture.indexOf("      let opening = context");
      const end = cancellationFixture.indexOf("      assert_false(secondary_ready.val)", start);
      assert(start >= 0 && end > start);
      writeFileSync(path.join(temporary, fixture), cancellationFixture.slice(0, start) +
        '      ignore(context.windows().open("secondary"))\n' + cancellationFixture.slice(end));
      replace(fixture, "        secondary_ready.val = true\n      } else {", `        secondary_ready.val = true
        fail("INJECTED_STARTUP_FAILURE")
      } else {`);
    }
    const result = spawnSync("moon", ["-C", "e2e", "run", "test", "--target", "native", "--", "--lifecycle-regressions"], {
      cwd: temporary,
      env: { ...process.env, PROTON_E2E_LIFECYCLE_CASE: "cancel-during-startup", MBT_PROTON_E2E_TIMEOUT_MS: "6000", CLEANUP_TEST_PRIMARY: primary ? "1" : "0" },
      encoding: "utf8", timeout: 300000, maxBuffer: 16 * 1024 * 1024,
    });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    console.log(`Window cleanup failure passed: ${primary ? "startup and destroy failures" : "cancellation and destroy failure"}`);
  }
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
