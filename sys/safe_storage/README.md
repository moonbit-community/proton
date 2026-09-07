# proton_safe_storage

OS-backed safe storage for native MoonBit applications. The current backend
uses Windows DPAPI and macOS Keychain. Linux reports unsupported until a
Secret Service backend is available; no plaintext or software-only fallback is
used.

The module supplies its own macOS Security framework link flags. Maintainers
can run `node scripts/test_safe_storage_macos.mjs` from the repository root to
check standalone linking and real CommonCrypto roundtrips with an isolated test
key; this test does not access the user's Keychain.
