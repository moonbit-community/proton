#!/usr/bin/env node

// Exercise public auto-launch output with real desktop-entry consumers.
import assert from "node:assert/strict";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

if (process.platform !== "linux") {
  console.log("[SKIP] Linux auto-launch consumer regression");
  process.exit(0);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: "utf8", timeout: 60000, ...options });
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `${command} ${args.join(" ")}\n${result.stdout}\n${result.stderr}`);
  return result.stdout.trim();
}

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const temporary = mkdtempSync(path.join(tmpdir(), "proton-autostart-"));
const identifier = `proton-test-${process.pid}`;
const unit = `app-${identifier.replaceAll("-", "\\x2d")}@autostart.service`;
let linked = false;
try {
  // Require a real user manager; silently skipping it would miss launch failures.
  run("systemctl", ["--user", "show-environment"]);
  cpSync(path.join(root, "sys/auto_launch"), temporary, {
    recursive: true,
    filter: source => !["_build", ".mooncakes"].includes(path.basename(source)),
  });
  mkdirSync(path.join(temporary, "main"));
  writeFileSync(path.join(temporary, "main/moon.pkg"), `
import { "moonbit-community/proton_auto_launch" @auto_launch, "moonbitlang/core/env" }
pkgtype(kind: "executable")
`);
  writeFileSync(path.join(temporary, "main/main.mbt"), `
fn main {
  let args = @env.args()
  let launcher = match @auto_launch.new("Literal autostart", path=args[1],
    identifier=${JSON.stringify(identifier)}, extra_arguments=args[2:].to_array()) {
    Ok(value) => value
    Err(error) => abort(error.to_string())
  }
  match launcher.enable() {
    Ok(_) => ()
    Err(error) => abort(error.to_string())
  }
}
`);
  run("moon", ["-C", temporary, "build", "--target", "native"]);
  const fixture = path.join(temporary, "_build/native/debug/build/main/main.exe");
  const resultFile = path.join(temporary, "argv.json");
  const app = path.join(temporary, "100%f% My App");
  writeFileSync(app, `#!/usr/bin/python3
import json, sys
with open(${JSON.stringify(resultFile)}, "w") as output:
    json.dump(sys.argv, output)
`, { mode: 0o700 });
  const home = path.join(temporary, "home");
  mkdirSync(home);
  const entry = path.join(home, ".config/autostart", identifier + ".desktop");
  const env = { ...process.env, HOME: home };

  writeFileSync(path.join(temporary, "launch.c"), `
#include <gio/gdesktopappinfo.h>
#include <sys/wait.h>
#include <errno.h>
static int status = -1;
static void launched(GDesktopAppInfo *app, GPid pid, gpointer data) {
  int result;
  do { result = waitpid(pid, &status, 0); } while (result < 0 && errno == EINTR);
  g_spawn_close_pid(pid);
  if (result < 0) status = -1;
}
int main(int argc, char **argv) {
  GDesktopAppInfo *app = g_desktop_app_info_new_from_filename(argv[1]);
  if (!app) { g_printerr("desktop entry rejected\\n"); return 1; }
  GError *error = NULL;
  gboolean ok = g_desktop_app_info_launch_uris_as_manager(app, NULL, NULL,
    G_SPAWN_DO_NOT_REAP_CHILD, NULL, NULL, launched, NULL, &error);
  if (!ok) { g_printerr("%s\\n", error->message); g_error_free(error); }
  g_object_unref(app);
  return ok && status >= 0 && WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}
`);
  const glib = path.join(temporary, "launch");
  run("cc", [path.join(temporary, "launch.c"), "-o", glib,
    ...run("pkg-config", ["--cflags", "--libs", "gio-unix-2.0"]).split(/\s+/)]);

  // GLib supports the full desktop-entry escaping grammar.
  const args = ["", "two words", "%f", "100%", "a\\b", 'a"b', "$HOME`id`", "line\nbreak\t\rend", "key=value", "你好"];
  run(fixture, [app, ...args], { env });
  run(glib, [entry]);
  assert.deepEqual(JSON.parse(readFileSync(resultFile)), [app, ...args]);
  rmSync(resultFile);
  console.log("GLib: percent executable path and literal arguments passed");

  // Older systemd generators mishandle backslash escapes (including dollars
  // and backticks). Keep this regression focused on percent paths and arguments.
  const systemdArgs = ["", "two words", "%f", "100%", 'a"b', "line\nbreak\t\rend", "key=value", "你好"];
  run(fixture, [app, ...systemdArgs], { env });
  const generated = path.join(temporary, "generated");
  mkdirSync(generated);
  run("/usr/lib/systemd/user-generators/systemd-xdg-autostart-generator",
    [generated, generated, generated], {
      env: { ...env, XDG_CONFIG_HOME: path.join(home, ".config"), XDG_CONFIG_DIRS: home },
    });
  run("systemctl", ["--user", "--runtime", "link", path.join(generated, unit)]);
  linked = true;
  run("systemctl", ["--user", "start", "--wait", unit]);
  assert.deepEqual(JSON.parse(readFileSync(resultFile)), [app, ...systemdArgs]);
  console.log("systemd: generated service launched the percent executable with exact arguments");
} finally {
  if (linked) {
    run("systemctl", ["--user", "stop", unit]);
    run("systemctl", ["--user", "--runtime", "disable", unit]);
    run("systemctl", ["--user", "daemon-reload"]);
  }
  rmSync(temporary, { recursive: true, force: true });
}
