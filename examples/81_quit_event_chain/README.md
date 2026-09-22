# Quit Event Chain

Manual review for Proton's Electron-style quit chain:
`.on_before_quit(...)`, `.on_will_quit(...)`, and `.on_quit(...)`, together
with the exit code adopted by `ApplicationContext::quit(exit_code=...)` and
`ApplicationContext::exit(exit_code=...)`.

Run it from a terminal so the quit steps and the process status are visible:

```sh
moon -C examples run 81_quit_event_chain --target native
echo $?
```

Every quit step prints one `[quit-chain]` line. Nothing in this example changes
system state or writes files, so the only cleanup is closing the window.

## Review steps

1. Press **Quit (0)**. The terminal must print `before-quit`, then `will-quit`,
   then `quit exit_code=0`, then `lifecycle shutdown`, and `echo $?` must report
   `0`.
2. Run the example again, press **Quit (3)**, and confirm the same order with
   `quit exit_code=3`; the shell status must be `3`.
3. Run the example again, press **Exit (7)**, and confirm that only
   `quit exit_code=7` and `lifecycle shutdown` are printed: `before-quit` and
   `will-quit` must be skipped while the window is destroyed immediately. The
   shell status must be `7`.
4. Run the example, press **Close the window**, and confirm the automatic
   last-window quit still runs `before-quit` → `will-quit` → `quit`.
5. Run the example, press **Block before-quit**, then press **Quit (0)**.
   `before-quit blocked=true` must be the last chain line, the window must stay
   open and usable, and the application must keep running.
6. Press **Block before-quit** again to allow the step, enable
   **Block will-quit**, and press **Quit (0)**. The window must close and
   `before-quit` → `will-quit blocked=true` must print, after which the
   application must stay alive without windows. Launch the same example again:
   the running instance keeps its identity and reopens the main window.
   Disable **Block will-quit**, then confirm the chain can quit normally.
7. Repeat step 5 or 6 with **Exit (7)**: a forced exit must ignore both
   toggles, destroy the window, print `quit exit_code=7`, and exit with status
   `7`.

## Platform matrix

- macOS: verified locally, including the terminal status after each step.
- Windows and Linux: CI compiles the example; the runtime review above still
  needs to be repeated there. Copyable prompt:
  ```text
  Build examples on <platform> and run `moon -C examples run 81_quit_event_chain
  --target native`. Follow README review steps 1-7 and report the terminal
  chain lines, the shell exit status, and whether a blocked before-quit or
  will-quit keeps the application usable.
  ```

Exit codes are process statuses, so a harness that wraps the application must
forward the child status instead of reporting its own.
