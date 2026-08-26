# Window Attention

This is a manual review example for Proton's Electron-style
`WindowHandle::flash_frame` API on macOS.

Run it with:

```sh
moon -C examples run 60_window_attention --target native
```

Review the application and its Dock icon:

1. Choose **Start in 3s**, then switch to another application before the
   countdown reaches zero. The Proton Dock icon should bounce continuously.
2. Activate the Proton application again. AppKit should stop the attention
   request automatically.
3. Choose **Run for 5s**, then switch to another application. The Dock icon
   should begin bouncing and stop after five seconds without activating Proton.
4. Repeat **Start in 3s** while staying in Proton. An active application should
   not visibly bounce its own Dock icon.
5. Choose **Stop** to exercise an explicit `flash_frame(false)` call. It should
   be safe when no request is active.

macOS attention is application-level even though Electron and Proton expose it
from a window handle. `true` uses a critical request, while `false` cancels the
request started by that window.
