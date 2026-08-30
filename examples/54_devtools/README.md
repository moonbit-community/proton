# DevTools and focus review

Manual review for Electron-style web contents focus and DevTools controls on
both the main browser and an embedded `WebContentsView`.

Run from the repository root:

```sh
moon -C examples run 54_devtools --target native
```

Review checklist:

1. Click **Focus view**. The right page should gain its green focus border,
   `View focused` should become `true`, and `Host focused` should become
   `false`.
2. Click **Focus page**. The host focus marker should return and the two native
   focus states should swap.
3. Open, close, and toggle host DevTools. Only `Host DevTools` should change.
4. Open, close, and toggle view DevTools. Only `View DevTools` should change.
5. Close either DevTools window directly and click **Refresh state**. The
   matching state should report `false` while the application remains open.
