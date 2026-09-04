# proton_safe_storage

OS-backed safe storage for native MoonBit applications. The current backend
uses Windows DPAPI and macOS Keychain. Linux reports unsupported until a
Secret Service backend is available; no plaintext or software-only fallback is
used.
