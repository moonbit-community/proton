# Lepus E2E Probes

This directory contains internal end-to-end probes for validating real Lepus
example applications. These packages are not user-facing examples.

`test` connects to a running CEF app through Chrome DevTools Protocol via
`justjavac/cdp`, evaluates scenario-specific checks in the loaded page, and
exits with success or failure for the launcher script.

Run the full smoke suite from the repository root:

```powershell
node .\scripts\e2e_cdp_smoke.mjs
```
