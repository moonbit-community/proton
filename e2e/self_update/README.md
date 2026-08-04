# Self-update scenario

A signed application installs a signed release of itself and restarts into the
new version. macOS only, which is where the updater is implemented.

```sh
moon -C e2e build --target native
e2e/self_update/run.sh
```

The script prints what happened and exits non-zero if any of it did not.

## What this covers that the unit tests cannot

`native/tests/proton_update_test.c` drives the replacement against throwaway
directories, and the MoonBit tests drive the refusals. Neither can cover the
three things that only exist in a real installation:

- the running bundle is found from the running executable, rather than supplied
  by a test hook,
- the chain runs against artifacts signed by a real RSA key, with real SHA-256
  digests and a real manifest,
- the replacement actually starts. The relaunched process writes its own line
  to `relaunched.txt`, and that line is the only evidence — by then the process
  that started it has exited,
- after recording that successful start, the replacement removes the older
  bundle that the atomic swap retained for launch recovery.

A passing run leaves `started 0.1.0` followed by `started 0.2.0`.

## What it does not cover

The three files are served from a directory rather than over HTTPS. Every URL
in the manifest is still an `https://` URL, because the schema refuses anything
else, and every check runs in the order it ships; only the transport is
replaced. Standing up a certificate the client would trust would test TLS, not
the updater.

## Things worth knowing before changing this

Launch Services **refuses to start an application under the per-user temporary
directory** (`$TMPDIR`, `/var/folders/...`), and reports success anyway — `open`
exits 0, `LSOpenFromURLSpec` returns 0, and the application never runs. This is
why the work directory defaults to `/tmp` and not `$TMPDIR`. It is also why
`proton_update_relaunch` promises only that the request was accepted.

`open` **does** pass its environment to the launched application, so the
relaunched process here inherits the same configuration. The version it reports
is read from its own bundle rather than from the environment, which is what
stops the check on launch from offering the same release forever.
