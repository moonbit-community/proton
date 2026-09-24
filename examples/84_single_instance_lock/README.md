# Single-Instance Lock

Manual review for Proton's single-instance runtime control:
`ApplicationContext::has_single_instance_lock()` and
`ApplicationContext::release_single_instance_lock()`, matching Electron's
`app.hasSingleInstanceLock()` and `app.releaseSingleInstanceLock()`.

Run the first instance from a terminal:

```sh
moon -C examples run 84_single_instance_lock --target native
```

The example owns the application identity (`.single_instance()`), prints the
session partition it uses, and releases the identity when you press **Release
lock**. Nothing outside the application data directory changes, and the only
cleanup is closing every instance you started.

## Review steps

1. The terminal must print
   `started with has_single_instance_lock=true partition=demo`. The page shows
   the same value as **hasSingleInstanceLock**.
2. Launch a second copy without changing anything:
   ```sh
   moon -C examples run 84_single_instance_lock --target native
   ```
   It must exit immediately after forwarding, and the first instance must print
   `activation forwarded to this instance (1)`: this is Electron's
   `second-instance` path delivered as `on_launch_input`.
3. Press **Release lock** in the first instance. The terminal must print
   `lock released; has_lock=false` and the page must report
   `hasSingleInstanceLock: false`.
4. Launch a third copy with its own profile so both can run side by side:
   ```sh
   PROTON_INSTANCE_DEMO_PARTITION=demo-2 \
     moon -C examples run 84_single_instance_lock --target native
   ```
   This copy must start its own window and print
   `started with has_single_instance_lock=true partition=demo-2` instead of
   forwarding: the released lock let it become primary. It shows no
   `activation forwarded` lines because it is a separate application identity
   holder now.
5. Launch a fourth copy with the same `demo-2` partition and confirm it
   forwards to the third instance, while the released first instance stays
   silent.
6. Close every window. Each process must print `lifecycle shutdown` and exit
   with status 0.

## Why the successor needs its own partition

Electron lets instances share one `userData` directory after a release. CEF owns
the browser profile exclusively and refuses to initialize a second process on
the same session data directory, so a side-by-side successor uses a different
`App::session_partition`. The identity lock is independent of the profile: a
successor with its own partition still acquires the released identity. Running
without `.single_instance()` is the other way to allow side-by-side instances;
Proton then uses a temporary profile.

## Platform matrix

- macOS (`darwin-arm64`): the headless e2e `--single-instance` probe is
  verified locally and covers forwarding, the runtime release, and a successor
  with its own partition becoming primary. The visible desktop review above
  still needs a human.
- Windows and Linux: the same probe runs in CI on both platforms. Repeat the
  steps above and report the terminal lines, the page state, and whether the
  successor started its own window.
