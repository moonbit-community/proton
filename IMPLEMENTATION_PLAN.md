# Registry-Safe Scaffold Plan

## Problem

The Todo scaffold currently references unpublished modules:

- `justjavac/proton_contract@0.1.0`
- `justjavac/proton_client@0.1.0`
- `justjavac/proton_rabbita@0.1.0`

The scaffold E2E replaces those registry dependencies with repository-local
workspace members before compiling. That proves source integration, but it does
not prove that an ordinary `proton_cli new` invocation can resolve the generated
project from the registry.

The template also references the already-published `proton@0.1.12` and
`proton_cli@0.1.9`, which do not contain the typed contract implementation used
by the new scaffold.

## Steps

1. Reproduce and codify the validation boundary.
   - Keep the source integration smoke explicit.
   - Add a registry-only scaffold smoke that never rewrites generated files.
   - Ensure documentation and output do not describe source integration as a
     registry validation.

2. Define a closed release dependency chain.
   - Assign new versions to changed published modules.
   - Make the generated template reference only versions from that release.
   - Extend release metadata validation and the maintainer release checklist to
     include contract, client, and Rabbita adapter modules.

3. Improve `new` failure diagnostics without hiding unavailable dependencies.
   - Detect dependency-resolution failures from `moon check`.
   - Explain that the generated project was rolled back and identify the
     required release chain.
   - Do not add local absolute paths or silently skip validation.

4. Verify.
   - Run template/unit/generated checks.
   - Run source integration E2E.
   - Run registry-only smoke and record its expected pre-release blocker.
   - After the dependency chain is published, the registry-only smoke must pass
     before releasing the CLI.

5. Remove this document after all code and documentation changes are complete.

## Acceptance Boundary

Before publication, local source integration can pass, but registry validation
must report the missing release chain. The generated scaffold is considered
release-ready only after the registry-only smoke passes without source
overrides.
