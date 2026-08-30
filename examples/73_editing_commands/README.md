# Editing Commands

Manual review for Electron-style editing commands on both `BrowserHandle` and
`ViewHandle`.

```sh
moon -C examples run 73_editing_commands --target native
```

1. Choose **Host browser** on the left, focus a host editor, type a suffix,
   then use **Undo** and **Redo**. Repeat after choosing **Web contents view**
   and focusing an editor on the right.
2. With the matching target selected, select a phrase and use **Cut**,
   **Undo**, **Copy**, and **Paste**. The selection readout and editor contents
   should track each operation.
3. Select a phrase and use **Delete**, then **Undo**. The deleted selection
   should return in that target only.
4. Focus either editor and use **Select all**. The active editor's content
   should become selected without affecting the other pane.
5. Select styled text in one rich editor and copy it. Select the other target,
   focus its rich editor, then compare **Paste** with **Paste match style**
   after resetting; the latter should use the destination formatting.

Repeat on macOS, Windows, and Linux. Each pane has its own focused frame and
editing history, so operations in one target must not modify the other.
