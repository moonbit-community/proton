# proton/ipc

`justjavac/proton/ipc` defines transport-neutral protocol types for Proton.

It does not know about WebView, WebSocket, process launch, or extension code.
The current root facade uses these types with the native DLL bridge.
